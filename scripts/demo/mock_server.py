import http.server
import json
import logging
from urllib.parse import urlparse

# Configure basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')

class MockApiHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        logging.info("%s - - [%s] %s\n" %
                     (self.address_string(),
                      self.log_date_time_string(),
                      format%args))

    def _send_json(self, status, payload):
        self.send_response(status)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(payload).encode('utf-8'))

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        # OpenAI Billing Usage
        if path == "/openai/v1/dashboard/billing/usage":
            self._send_json(200, {
                "total_usage": 1500,
                "daily_costs": [
                    {"timestamp": 1600000000, "line_items": [{"name": "gpt-4", "cost": 150}]}
                ]
            })
            return

        # OpenAI Billing Subscription (Budget)
        if path == "/openai/v1/dashboard/billing/subscription":
            self._send_json(200, {
                "hard_limit_usd": 120.0,
                "soft_limit_usd": 100.0
            })
            return

        # Anthropic Workspaces (for Anthropic provider)
        if path == "/anthropic/v1/workspaces":
            self._send_json(200, {
                "type": "list",
                "data": [
                    {
                        "type": "workspace",
                        "id": "wksp_123",
                        "name": "Default Workspace"
                    }
                ]
            })
            return
            
        # Google Usage (Mock endpoint structure)
        if path == "/google/v1/projects/demo/usage":
            self._send_json(200, {
                "usage": 2.50
            })
            return

        # Copilot Org Usage
        if path.startswith("/copilot/orgs/"):
            self._send_json(200, {
                "total_seats": 50,
                "active_users": 23
            })
            return

        # Claude Code (claude.ai) bootstrap — account + org UUID + plan
        if path == "/claude/api/bootstrap":
            self._send_json(200, {
                "account": {
                    "uuid": "acct_demo",
                    "memberships": [
                        {
                            "organization": {
                                "uuid": "org_demo_123",
                                "subscription": {"type": "max_20x"},
                                "rate_limit_tier": "scale_max_20x"
                            }
                        }
                    ]
                }
            })
            return

        # Claude Code usage — percentage-based, mirroring the real claude.ai API.
        if path.startswith("/claude/api/organizations/") and path.endswith("/usage"):
            self._send_json(200, {
                "five_hour": {"utilization": 42.0, "resets_at": "2099-01-01T00:00:00Z"},
                "seven_day": {"utilization": 18.0, "resets_at": "2099-01-07T00:00:00Z"},
                "extra_usage": {
                    "is_enabled": True,
                    "monthly_limit": 50.0,
                    "used_credits": 12.34,
                    "resets_at": "2099-02-01T00:00:00Z"
                },
                "limits": [
                    {"kind": "session", "group": "session", "percent": 42, "severity": "normal", "is_active": True},
                    {"kind": "weekly_all", "group": "weekly", "percent": 18, "severity": "normal", "is_active": False},
                    {"kind": "weekly_scoped", "group": "weekly", "percent": 5, "severity": "normal",
                     "scope": {"model": {"display_name": "Fable"}}, "is_active": False}
                ]
            })
            return

        # Default Not Found
        self._send_json(404, {"error": "Not Found"})

    def do_POST(self):
        self._send_json(200, {"status": "ok"})

def run(port=8080):
    server_address = ('', port)
    httpd = http.server.HTTPServer(server_address, MockApiHandler)
    logging.info(f"Starting mock API server on port {port}...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
    logging.info("Server stopped.")

if __name__ == '__main__':
    run()