"""
Lightweight Django-style Hospital Management API
Built for DCKAP/JRDVOP DevOps portfolio demonstration.
"""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

# ---------------------------------------------------------------------------
# Simulated in-memory patient data (replace with Django+MySQL in production)
# ---------------------------------------------------------------------------
PATIENTS = [
    {"id": 1, "name": "Alice Sharma",   "age": 34, "diagnosis": "Hypertension"},
    {"id": 2, "name": "Ravi Kumar",     "age": 56, "diagnosis": "Diabetes Type-2"},
    {"id": 3, "name": "Priya Nair",     "age": 28, "diagnosis": "Asthma"},
]


class HospitalHandler(BaseHTTPRequestHandler):
    """Handles HTTP GET requests for the Hospital Management API."""

    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        # SOC2 / OWASP security headers
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._send_json(200, {"status": "healthy", "service": "hospital-management"})

        elif self.path == "/patients":
            self._send_json(200, {"patients": PATIENTS, "count": len(PATIENTS)})

        elif self.path.startswith("/patients/"):
            try:
                patient_id = int(self.path.split("/")[-1])
                patient = next((p for p in PATIENTS if p["id"] == patient_id), None)
                if patient:
                    self._send_json(200, patient)
                else:
                    self._send_json(404, {"error": "Patient not found"})
            except ValueError:
                self._send_json(400, {"error": "Invalid patient ID"})

        elif self.path == "/":
            self._send_json(200, {
                "service": "Hospital Management System",
                "version": "1.0.0",
                "endpoints": ["/health", "/patients", "/patients/<id>"],
            })
        else:
            self._send_json(404, {"error": "Endpoint not found"})

    def log_message(self, fmt, *args):  # suppress default Apache-style logs
        pass


if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    server = HTTPServer((host, port), HospitalHandler)
    print(f"Hospital API listening on {host}:{port}")
    server.serve_forever()
