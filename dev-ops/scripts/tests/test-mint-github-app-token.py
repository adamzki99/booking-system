import importlib.util
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[2] / "factory" / "lib" / "mint_github_app_token.py"
SPEC = importlib.util.spec_from_file_location("mint_github_app_token", MODULE_PATH)
mint = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mint)


def _args(monkeypatch, *extra):
    monkeypatch.setattr(
        mint.sys,
        "argv",
        ["mint_github_app_token.py", "--app-id", "123", "--key-file", "key.pem", *extra],
    )
    monkeypatch.setattr(mint, "_read_key", lambda _path: "private-key")
    monkeypatch.setattr(mint, "_jwt", lambda _app_id, _key: "app-jwt")


def test_print_app_slug_uses_app_jwt(monkeypatch, capsys):
    _args(monkeypatch, "--print-app-slug")
    calls = []

    def request(method, url, token, data=None):
        calls.append((method, url, token, data))
        return 200, {"slug": "booking-factory"}

    monkeypatch.setattr(mint, "_request", request)

    assert mint.main() == 0
    assert capsys.readouterr().out == "booking-factory"
    assert calls == [("GET", "https://api.github.com/app", "app-jwt", None)]


def test_mint_token_discovers_installation(monkeypatch, capsys):
    _args(monkeypatch, "--repo", "owner/repo")
    calls = []

    def request(method, url, token, data=None):
        calls.append((method, url, token, data))
        if method == "GET":
            return 200, {"id": 42}
        return 201, {"token": "installation-token"}

    monkeypatch.setattr(mint, "_request", request)

    assert mint.main() == 0
    assert capsys.readouterr().out == "installation-token"
    assert calls[0] == (
        "GET",
        "https://api.github.com/repos/owner/repo/installation",
        "app-jwt",
        None,
    )
    assert calls[1] == (
        "POST",
        "https://api.github.com/app/installations/42/access_tokens",
        "app-jwt",
        {},
    )


def test_print_app_slug_reports_lookup_failure(monkeypatch, capsys):
    _args(monkeypatch, "--print-app-slug")
    monkeypatch.setattr(mint, "_request", lambda *_args, **_kwargs: (401, {"message": "bad jwt"}))

    assert mint.main() == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert "app lookup failed" in captured.err
