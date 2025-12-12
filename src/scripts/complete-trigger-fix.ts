import { DataSource } from 'typeorm';
import { config } from 'dotenv';

config();

async function dropAndRecreate() {
    const dataSource = new DataSource({
        type: 'postgres',
        url: process.env.DATABASE_URL,
    });

    try {
        console.log('Connecting to database...');
        await dataSource.initialize();
        console.log('✅ Connected!\n');

        // Drop the old function and trigger completely
        console.log('Step 1: Dropping old trigger and function...');
        await dataSource.query(`
      DROP TRIGGER IF EXISTS create_user_dependents ON users;
      DROP FUNCTION IF EXISTS trigger_create_user_dependents_after_insert() CASCADE;
      DROP FUNCTION IF EXISTS trigger_create_user_dependents() CASCADE;
    `);
        console.log('✅ Old triggers/functions dropped\n');

        // Create the new function with roles array
        console.log('Step 2: Creating new function with roles array...');
        await dataSource.query(`
      CREATE OR REPLACE FUNCTION trigger_create_user_dependents()
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
    `);
        console.log('✅ Function created\n');

        // Create the trigger
        console.log('Step 3: Creating trigger...');
        await dataSource.query(`
      CREATE TRIGGER create_user_dependents
      AFTER INSERT ON users
      FOR EACH ROW
      EXECUTE FUNCTION trigger_create_user_dependents();
    `);
        console.log('✅ Trigger created\n');

        // Verify
        console.log('Step 4: Verifying...');
        const triggers = await dataSource.query(`
      SELECT t.tgname, p.proname 
      FROM pg_trigger t
      JOIN pg_proc p ON t.tgfoid = p.oid
      JOIN pg_class c ON t.tgrelid = c.oid
      WHERE c.relname = 'users' AND NOT t.tgisinternal;
    `);
        console.log('Active triggers on users table:', triggers);
        console.log('\n✅ Complete! The trigger should now work with the roles array.');

    } catch (error) {
        console.error('❌ Error:', error);
        process.exit(1);
    } finally {
        await dataSource.destroy();
    }
}

dropAndRecreate();
