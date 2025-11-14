import http.server
import socketserver
import webbrowser
import os
from pathlib import Path

PORT = 8000
DIRECTORY = Path(__file__).parent

class MyHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(DIRECTORY), **kwargs)

os.chdir(DIRECTORY)

with socketserver.TCPServer(("", PORT), MyHTTPRequestHandler) as httpd:
    print(f"🚀 Server running at http://localhost:{PORT}")
    print(f"📊 Opening dashboard in browser...")
    print(f"Press Ctrl+C to stop the server\n")
    
    # Open browser automatically
    webbrowser.open(f'http://localhost:{PORT}/dashboard.html')
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n✅ Server stopped")
