const https = require('https');

const data = JSON.stringify({
    phoneNumber: '1234567890'
    // Missing OTP
});

const options = {
    hostname: 'ride-andhra-baceknd-final.onrender.com',
    port: 443,
    path: '/auth/verify-otp',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length
    }
};

console.log(`Testing Invalid Body to ${options.path}`);

const req = https.request(options, (res) => {
    console.log(`statusCode: ${res.statusCode}`);
    let body = '';
    res.on('data', (d) => { body += d; });
    res.on('end', () => {
        console.log('Body:', body);
    });
});

req.write(data);
req.end();
