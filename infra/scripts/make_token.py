"""Gera um JWT HS256 de teste (mesmo formato que o Backend emite), pra
iterar em RLS/RPC via curl/psql sem precisar logar de verdade no app.

Uso: python3 backend/scripts/make_token.py <uid> [role]
Lê o segredo de backend/.env (INTERNAL_JWT_SECRET).
"""
import os
import sys
import time

import jwt


def load_env(path: str) -> dict:
    values = {}
    if not os.path.exists(path):
        return values
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


def main() -> None:
    if len(sys.argv) < 2:
        print(
            "Uso: python3 backend/scripts/make_token.py <uid> [email] [role]",
            file=sys.stderr,
        )
        sys.exit(1)

    uid = sys.argv[1]
    email = sys.argv[2] if len(sys.argv) > 2 else None
    role = sys.argv[3] if len(sys.argv) > 3 else "web_user"

    env = load_env(os.path.join(os.path.dirname(__file__), "..", ".env"))
    secret = env.get("INTERNAL_JWT_SECRET", "dev-secret-troque-isto")

    now = int(time.time())
    payload = {"sub": uid, "email": email, "role": role, "iat": now, "exp": now + 3600}
    token = jwt.encode(payload, secret, algorithm="HS256")
    print(token)


if __name__ == "__main__":
    main()
