# Archivo de control con malas prácticas A PROPÓSITO. No se ejecuta nunca:
# sirve para demostrar que las reglas de semgrep/rules.yaml detectan cada caso.
import os, subprocess, pickle, yaml, logging
from fastapi.middleware.cors import CORSMiddleware
eval(x)
subprocess.run(cmd, shell=True)
os.system(cmd)
pickle.loads(data)
yaml.load(s)
app.add_middleware(CORSMiddleware, allow_origins=["*"])
logging.info("guardé %s", entry.content)
print(payload.content)
