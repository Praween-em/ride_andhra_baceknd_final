import { DataSource } from 'typeorm';
import { config } from 'dotenv';

config();

async function simpleCheck() {
    const dataSource = new DataSource({
        type: 'postgres',
        url: process.env.DATABASE_URL,
    });

    try {
        await dataSource.initialize();
        console.log('Connected!\n');

        // Simple check - does the function source contain 'NEW.role' or 'NEW.roles'?
        const result = await dataSource.query(`
      SELECT 
        p.proname as name,
        p.prosrc as source
      FROM pg_proc p
      WHERE p.proname LIKE '%trigger_create_user%'
      AND p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
    `);

        console.log('Functions found:');
        for (const func of result) {
            console.log(`\nFunction: ${func.name}`);
            console.log('-'.repeat(50));
            console.log(func.source);
            console.log('-'.repeat(50));

            if (func.source.includes('NEW.role ')) {
                console.log('❌ Contains OLD pattern: NEW.role');
            } else if (func.source.includes('NEW.roles')) {
                console.log('✅ Contains NEW pattern: NEW.roles');
            }
        }

        await dataSource.destroy();
    } catch (error) {
        console.error('Error:', error);
        process.exit(1);
    }
}

simpleCheck();
