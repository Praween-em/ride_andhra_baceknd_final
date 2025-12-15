const https = require('https');

const data = JSON.stringify({
    phoneNumber: '1234567890',
    otp: '123456'
});

const options = {
    hostname: 'ride-andhra-baceknd-final.onrender.com', // Fixed typo in URL if it was consistent with previous user input, but user provided access to 'ride-andhra-baceknd-final.onrender.com' in prompt. 
    // Wait, user wrote 'ride-andhra-baceknd-final.onrender.com' in the prompt. 'baceknd' is a typo but might be the actual URL.
    // Previous successful root test used: ride-andhra-baceknd-final.onrender.com
    // I will use that.
    port: 443,
    path: '/auth/verify-otp',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length
    }
};

console.log(`Testing ${options.method} https://${options.hostname}${options.path}`);

const req = https.request(options, (res) => {
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
