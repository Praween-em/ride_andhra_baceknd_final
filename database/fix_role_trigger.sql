-- Quick fix for the role trigger issue
-- This updates the trigger function to use 'roles' array instead of 'role'

CREATE OR REPLACE FUNCTION trigger_create_user_dependents()
RETURNS TRIGGER AS $$
BEGIN
    -- Create wallet for every user
    INSERT INTO wallets (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;

    -- Create rider profile if user has 'rider' role
    IF 'rider' = ANY(NEW.roles) THEN
        INSERT INTO rider_profiles (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
    END IF;
    
    -- Create driver profile if user has 'driver' role
    IF 'driver' = ANY(NEW.roles) THEN
        INSERT INTO driver_profiles (user_id, first_name, last_name)
        VALUES (NEW.id, SPLIT_PART(COALESCE(NEW.name,''),' ',1), COALESCE(SPLIT_PART(NEW.name,' ',2), ''))
        ON CONFLICT DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
