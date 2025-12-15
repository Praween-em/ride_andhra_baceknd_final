const http = require('http');

const data = JSON.stringify({
    phoneNumber: '1234567890',
    otp: '123456'
});

const options = {
    hostname: 'localhost',
    port: 3000,
    path: '/auth/verify-otp',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length
    }
};

console.log(`Testing POST http://${options.hostname}:${options.port}${options.path}`);

const req = http.request(options, (res) => {
    console.log(`statusCode: ${res.statusCode}`);
    let body = '';
    res.on('data', (d) => { body += d; });
    res.on('end', () => {
        console.log('Body:', body);
    });
});

req.on('error', (error) => {
    console.error('Error:', error);
});

req.write(data);
req.end();
