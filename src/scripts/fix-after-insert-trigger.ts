/**
 * Fix the AFTER INSERT trigger function to use roles array
 */
import { DataSource } from 'typeorm';
import { config } from 'dotenv';

config();

const migrationSQL = `
-- Fix trigger_create_user_dependents_after_insert to use roles array
CREATE OR REPLACE FUNCTION trigger_create_user_dependents_after_insert()
RETURNS TRIGGER AS $$
BEGIN
    -- Create wallet (always)
    INSERT INTO wallets (user_id) 
    VALUES (NEW.id) 
    ON CONFLICT (user_id) DO NOTHING;

    -- Create rider profile if user has 'rider' role
    IF 'rider' = ANY(NEW.roles) THEN
        INSERT INTO rider_profiles (user_id) 
        VALUES (NEW.id) 
        ON CONFLICT (user_id) DO NOTHING;
    END IF;

    -- Create driver profile if user has 'driver' role  
    IF 'driver' = ANY(NEW.roles) THEN
        INSERT INTO driver_profiles (
            user_id, 
            first_name, 
            last_name
        )
        VALUES (
            NEW.id,
            SPLIT_PART(COALESCE(NEW.name, ''), ' ', 1),
            COALESCE(SPLIT_PART(NEW.name, ' ', 2), '')
        )
        ON CONFLICT (user_id) DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
`;

async function runMigration() {
    const dataSource = new DataSource({
        type: 'postgres',
        url: process.env.DATABASE_URL,
    });

    try {
        console.log('Connecting to database...');
        await dataSource.initialize();
        console.log('✅ Connected!\n');

        console.log('Updating trigger_create_user_dependents_after_insert...');
        await dataSource.query(migrationSQL);
        console.log('✅ Trigger function updated successfully!\n');

        // Verify the fix
        const check = await dataSource.query(`
      SELECT pg_get_functiondef(
        (SELECT oid FROM pg_proc WHERE proname = 'trigger_create_user_dependents_after_insert')
      ) as definition;
    `);

        if (check[0]?.definition?.includes('NEW.role')) {
            console.log('❌ WARNING: Function still contains NEW.role!');
        } else {
            console.log('✅ Verified: Function now uses NEW.roles array');
        }

    } catch (error) {
        console.error('❌ Migration failed:', error);
        process.exit(1);
    } finally {
        await dataSource.destroy();
    }
}

runMigration();
