from flask import Flask, request, jsonify
from sentence_transformers import SentenceTransformer
import numpy as np

app = Flask(__name__)
model = SentenceTransformer("all-MiniLM-L6-v2")


@app.route("/embed", methods=["POST"])
def embed():
    texts = request.json.get("texts", [])
    embeddings = model.encode(texts).tolist()
    return jsonify({"embeddings": embeddings})


@app.route("/similarity", methods=["POST"])
def similarity():
    data = request.json
    a = data.get("a", "")
    b = data.get("b", "")
    vecs = model.encode([a, b])
    cos_sim = float(np.dot(vecs[0], vecs[1]) / (np.linalg.norm(vecs[0]) * np.linalg.norm(vecs[1])))
    return jsonify({"similarity": cos_sim})


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
