const http = require('http');

const PORT = 8000;

const server = http.createServer((req, res) => {
  const payload = {
    service: 'sample-app',
    message: 'Hello from the sample backend!',
    version: '1.0.0',
    path: req.url,
    timestamp: new Date().toISOString()
  };

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
});

server.listen(PORT, () => {
  console.log(`Sample app listening on port ${PORT}`);
});
