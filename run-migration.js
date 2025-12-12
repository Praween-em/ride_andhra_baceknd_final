require('dotenv').config();
const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

async function runMigration() {
    const client = new Client({
        connectionString: process.env.DATABASE_URL,
    });

    try {
        await client.connect();
        console.log('Connected to database');

        const sqlFile = path.join(__dirname, 'database', 'migrate_role_to_roles.sql');
        const sql = fs.readFileSync(sqlFile, 'utf8');

        console.log('Running migration...');
        await client.query(sql);
        console.log('✅ Migration completed successfully!');
    } catch (error) {
        console.error('❌ Migration failed:', error.message);
        process.exit(1);
    } finally {
        await client.end();
    }
}

runMigration();
