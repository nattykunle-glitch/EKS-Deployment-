from flask import Flask, jsonify
import socket
import os

app = Flask(__name__)

@app.route("/")
def hello():
    return jsonify({
        "message": "Hello, World!",
        "hostname": socket.gethostname(),
        "version": os.getenv("APP_VERSION", "v1")
    })

@app.route("/healthz")
def healthz():
    return jsonify({"status": "ok"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
