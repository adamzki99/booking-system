#!/usr/bin/env node
// Validate opencode.jsonc against the schema it declares in "$schema".
//
// Usage:
//   node dev-ops/scripts/validate-opencode-config.mjs [--file PATH] [--schema PATH_OR_URL]
//
// The default file is opencode.jsonc at the repository root and the default
// schema is the config's own "$schema" value. CI fetches the published schema,
// so an unknown or misspelled key fails the check instead of being dropped
// silently at runtime.

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import { parse, printParseErrorCode } from "jsonc-parser";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "../..");

function usage() {
  console.error("usage: validate-opencode-config.mjs [--file PATH] [--schema PATH_OR_URL]");
}

function parseArgs(argv) {
  const options = {
    file: resolve(repoRoot, "opencode.jsonc"),
    schema: process.env.OPENCODE_CONFIG_SCHEMA || "",
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--file" && argv[i + 1]) {
      options.file = resolve(process.cwd(), argv[++i]);
    } else if (arg === "--schema" && argv[i + 1]) {
      options.schema = argv[++i];
    } else if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else {
      console.error(`unknown argument: ${arg}`);
      usage();
      process.exit(2);
    }
  }
  return options;
}

async function loadSchema(ref) {
  if (!/^https?:\/\//i.test(ref)) {
    return JSON.parse(await readFile(resolve(process.cwd(), ref), "utf8"));
  }

  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(ref, {
        headers: { accept: "application/json" },
        signal: AbortSignal.timeout(20_000),
      });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status} ${response.statusText}`);
      }
      return await response.json();
    } catch (error) {
      lastError = error;
      if (attempt < 3) {
        await new Promise((resolveDelay) => setTimeout(resolveDelay, attempt * 1_000));
      }
    }
  }
  throw new Error(`could not fetch schema ${ref}: ${lastError.message}`);
}

function formatPath(instancePath) {
  return instancePath === "" ? "/" : instancePath;
}

function collectRefs(value, refs = []) {
  if (Array.isArray(value)) {
    for (const item of value) collectRefs(item, refs);
  } else if (value && typeof value === "object") {
    if (typeof value.$ref === "string") refs.push(value.$ref);
    for (const item of Object.values(value)) collectRefs(item, refs);
  }
  return refs;
}

async function addExternalSchemas(ajv, rootSchema, rootRef) {
  const seen = new Set([rootRef.split("#")[0]]);
  const queue = [rootSchema];
  while (queue.length > 0) {
    const schema = queue.shift();
    for (const ref of collectRefs(schema)) {
      const url = ref.split("#")[0];
      if (!/^https?:\/\//i.test(url) || seen.has(url)) continue;
      seen.add(url);
      const external = await loadSchema(url);
      ajv.addSchema(external, url);
      queue.push(external);
    }
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  let text;
  try {
    text = await readFile(options.file, "utf8");
  } catch (error) {
    console.error(`could not read ${options.file}: ${error.message}`);
    process.exit(1);
  }

  const parseErrors = [];
  const config = parse(text, parseErrors, {
    allowTrailingComma: true,
    disallowComments: false,
  });
  if (parseErrors.length > 0) {
    for (const error of parseErrors) {
      console.error(`${options.file}:${error.offset} ${printParseErrorCode(error.error)}`);
    }
    process.exit(1);
  }
  if (config === undefined || typeof config !== "object" || config === null) {
    console.error(`${options.file}: top-level value must be an object`);
    process.exit(1);
  }

  const schemaRef = options.schema || config.$schema;
  if (!schemaRef) {
    console.error(`${options.file}: missing "$schema"`);
    process.exit(1);
  }

  let schema;
  try {
    schema = await loadSchema(schemaRef);
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }

  const ajv = new Ajv2020({
    allErrors: true,
    strict: false,
    validateFormats: false,
  });
  let validate;
  try {
    await addExternalSchemas(ajv, schema, schemaRef);
    validate = ajv.compile(schema);
  } catch (error) {
    console.error(`schema ${schemaRef} is not usable: ${error.message}`);
    process.exit(1);
  }

  if (validate(config)) {
    console.log(`OK: ${options.file} matches ${schemaRef}`);
    return;
  }

  console.error(`INVALID: ${options.file} does not match ${schemaRef}`);
  for (const error of validate.errors ?? []) {
    const params = error.params ? ` ${JSON.stringify(error.params)}` : "";
    console.error(`  ${formatPath(error.instancePath)} ${error.message}${params}`);
  }
  process.exit(1);
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
