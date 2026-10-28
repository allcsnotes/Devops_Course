// Tiny demo storefront dev server for M01-L04 (stands in for the real web app's dev server)
const http = require('http');
const fs = require('fs');
const path = require('path');
const PORT = 3000;
const page = fs.readFileSync(path.join(__dirname, 'index.html'));
http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(page);
}).listen(PORT, () => {
  console.log(`storefront ready on http://localhost:${PORT}`);
});
