require('dotenv').config();
const { Client } = require('pg');

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
    console.error('DATABASE_URL not found in environment');
    process.exit(1);
}

// Mask password for logging
const masked = connectionString.replace(/:([^:@]+)@/, ':****@');
console.log('Connecting to:', masked);

const client = new Client({
    connectionString: connectionString,
});

async function fixDatabase() {
    try {
        await client.connect();
        console.log('Connected successfully.');

        console.log('Dropping view driver_app_drivers...');
        await client.query('DROP VIEW IF EXISTS driver_app_drivers CASCADE;');
        console.log('View dropped successfully.');

    } catch (err) {
        console.error('Error executing script:', err);
    } finally {
        await client.end();
    }
}

fixDatabase();
