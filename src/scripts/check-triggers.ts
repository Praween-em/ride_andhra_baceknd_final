import { DataSource } from 'typeorm';
import { config } from 'dotenv';

config();

async function checkTriggers() {
    const dataSource = new DataSource({
        type: 'postgres',
        url: process.env.DATABASE_URL,
    });

    try {
        await dataSource.initialize();
        console.log('Connected to database\n');

        // Check all triggers on users table
        const triggers = await dataSource.query(`
      SELECT 
        t.tgname AS trigger_name,
        p.proname AS function_name,
        pg_get_functiondef(p.oid) AS function_definition
      FROM pg_trigger t
      JOIN pg_proc p ON t.tgfoid = p.oid
      JOIN pg_class c ON t.tgrelid = c.oid
      WHERE c.relname = 'users'
      AND NOT t.tgisinternal
      ORDER BY t.tgname;
    `);

        console.log('=== TRIGGERS ON USERS TABLE ===\n');
        for (const trigger of triggers) {
            console.log(`Trigger: ${trigger.trigger_name}`);
            console.log(`Function: ${trigger.function_name}`);
            console.log('Definition:');
            console.log(trigger.function_definition);
            console.log('\n' + '='.repeat(80) + '\n');
        }

        // Check if any function contains NEW.role
        const problematicFuncs = await dataSource.query(`
      SELECT 
        p.proname AS function_name,
        pg_get_functiondef(p.oid) AS function_definition
      FROM pg_proc p
      WHERE pg_get_functiondef(p.oid) LIKE '%NEW.role%'
      AND p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
    `);

        if (problematicFuncs.length > 0) {
            console.log('⚠️  FUNCTIONS STILL REFERENCING NEW.role:\n');
            for (const func of problematicFuncs) {
                console.log(`Function: ${func.function_name}`);
                console.log(func.function_definition);
                console.log('\n' + '='.repeat(80) + '\n');
            }
        } else {
            console.log('✅ No functions found referencing NEW.role\n');
        }

        await dataSource.destroy();
    } catch (error) {
        console.error('Error:', error);
        process.exit(1);
    }
}

checkTriggers();
