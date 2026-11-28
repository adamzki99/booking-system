#!/usr/bin/env bash
# Validate opencode.jsonc against the schema it declares in "$schema".
#
# Usage:
#   bash dev-ops/scripts/validate-opencode-config.sh [--file PATH] [--schema PATH_OR_URL]
#
# The default file is opencode.jsonc at the repository root and the default
# schema is the config's own "$schema" value (or $OPENCODE_CONFIG_SCHEMA).
# CI fetches the published schema, so an unknown or misspelled key fails the
# check instead of being dropped silently at runtime.
#
# This is a bash script; it drives the repository-local `ajv` (draft 2020-12)
# and `jsonc-parser` Node packages through `node` for the JSON Schema step.

set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

usage() {
  echo "usage: ${SCRIPT_NAME} [--file PATH] [--schema PATH_OR_URL]" >&2
}

file="${REPO_ROOT}/opencode.jsonc"
schema="${OPENCODE_CONFIG_SCHEMA:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "unknown argument: $1" >&2
        usage
        exit 2
      fi
      file="$2"
      shift 2
      ;;
    --schema)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "unknown argument: $1" >&2
        usage
        exit 2
      fi
      schema="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Resolve a possibly-relative --file against the current working directory.
case "$file" in
  /*) ;;
  *) file="${PWD}/${file}" ;;
esac

if [[ ! -e "$file" ]]; then
  echo "could not read ${file}: file not found" >&2
  exit 1
fi

export OPENCODE_CONFIG_FILE="$file"
export OPENCODE_CONFIG_SCHEMA_REF="$schema"
export OPENCODE_REPO_ROOT="$REPO_ROOT"

# Read the program from the heredoc on stdin. Resolve the repository-local
# `ajv` and `jsonc-parser` packages relative to the repo root, not the cwd.
node --input-type=module - <<'NODE'
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createRequire } from "node:module";

const require = createRequire(`file://${process.env.OPENCODE_REPO_ROOT.replace(/\/+$/, "")}/`);
const Ajv2020 = require("ajv/dist/2020.js");
const { parse, printParseErrorCode } = require("jsonc-parser");

const file = process.env.OPENCODE_CONFIG_FILE;
const schemaArg = process.env.OPENCODE_CONFIG_SCHEMA_REF || "";

function formatPath(instancePath) {
  return instancePath === "" ? "/" : instancePath;
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

let text;
try {
  text = await readFile(file, "utf8");
} catch (error) {
  console.error(`could not read ${file}: ${error.message}`);
  process.exit(1);
}

const parseErrors = [];
const config = parse(text, parseErrors, {
  allowTrailingComma: true,
  disallowComments: false,
});
if (parseErrors.length > 0) {
  for (const error of parseErrors) {
    console.error(`${file}:${error.offset} ${printParseErrorCode(error.error)}`);
  }
  process.exit(1);
}
if (config === undefined || typeof config !== "object" || config === null) {
  console.error(`${file}: top-level value must be an object`);
  process.exit(1);
}

const schemaRef = schemaArg || config.$schema;
if (!schemaRef) {
  console.error(`${file}: missing "$schema"`);
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
  console.log(`OK: ${file} matches ${schemaRef}`);
  process.exit(0);
}

console.error(`INVALID: ${file} does not match ${schemaRef}`);
for (const error of validate.errors ?? []) {
  const params = error.params ? ` ${JSON.stringify(error.params)}` : "";
  console.error(`  ${formatPath(error.instancePath)} ${error.message}${params}`);
}
process.exit(1);
NODE
