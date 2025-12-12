-- Migration: Update from single 'role' to 'roles' array
-- Step 1: Add the new 'roles' column (array type)
ALTER TABLE users ADD COLUMN IF NOT EXISTS roles user_role_enum[];

-- Step 2: Migrate existing role data to roles array
UPDATE users SET roles = ARRAY[role] WHERE roles IS NULL;

-- Step 3: Set default for new rows
ALTER TABLE users ALTER COLUMN roles SET DEFAULT ARRAY['rider'::user_role_enum];

-- Step 4: Make roles NOT NULL
ALTER TABLE users ALTER COLUMN roles SET NOT NULL;

-- Step 5: Drop the view that depends on the old role column
DROP VIEW IF EXISTS driver_app_drivers CASCADE;

-- Step 6: Recreate the view using the new 'roles' column
CREATE OR REPLACE VIEW driver_app_drivers AS
SELECT
    u.id,
    u.phone_number,
    dp.first_name,
    dp.last_name,
    u.profile_image AS profile_picture_url,
    dp.vehicle_type,
    dp.vehicle_plate_number AS vehicle_registration_number,
    dp.is_available,
    u.created_at,
    u.updated_at
FROM users u
JOIN driver_profiles dp ON u.id = dp.user_id
WHERE 'driver' = ANY(u.roles);

-- Step 7: Recreate the update trigger for the view
CREATE OR REPLACE FUNCTION handle_driver_app_drivers_update()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE users
    SET phone_number = NEW.phone_number,
        profile_image = NEW.profile_picture_url,
        updated_at = NOW()
    WHERE id = OLD.id;

    UPDATE driver_profiles
    SET first_name = NEW.first_name,
        last_name = NEW.last_name,
        vehicle_type = NEW.vehicle_type,
        vehicle_plate_number = NEW.vehicle_registration_number,
        is_available = NEW.is_available,
        updated_at = NOW()
    WHERE user_id = OLD.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_instead_of_update_on_driver_app_drivers ON driver_app_drivers;
CREATE TRIGGER trg_instead_of_update_on_driver_app_drivers
INSTEAD OF UPDATE ON driver_app_drivers
FOR EACH ROW
EXECUTE FUNCTION handle_driver_app_drivers_update();

-- Step 8: Update the user dependents trigger to use roles array
CREATE OR REPLACE FUNCTION trigger_create_user_dependents()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO wallets (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;

    IF 'rider' = ANY(NEW.roles) THEN
        INSERT INTO rider_profiles (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
    END IF;
    
    IF 'driver' = ANY(NEW.roles) THEN
        INSERT INTO driver_profiles (user_id, first_name, last_name)
        VALUES (NEW.id, SPLIT_PART(COALESCE(NEW.name,''),' ',1), COALESCE(SPLIT_PART(NEW.name,' ',2), ''))
        ON CONFLICT DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 9: Drop old role column now that everything uses roles
ALTER TABLE users DROP COLUMN IF EXISTS role;
