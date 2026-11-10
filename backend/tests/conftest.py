import os

# Precisa ser setado antes de qualquer `from app...` importar app.config,
# que instancia `Settings()` (e valida campos obrigatórios) no import.
os.environ.setdefault("FIREBASE_PROJECT_ID", "test-project")
os.environ.setdefault("INTERNAL_JWT_SECRET", "test-secret-00000000000000000000000000")
