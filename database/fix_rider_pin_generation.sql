-- =========================================
-- FIX: Rider PIN Not Being Created
-- =========================================
-- This script fixes the issue where rider_pin is NULL
-- by splitting the trigger into BEFORE and AFTER INSERT triggers

-- =========================================
-- 1. FUNCTION: Generate Unique PIN
-- =========================================
CREATE OR REPLACE FUNCTION generate_unique_pin()
RETURNS VARCHAR(4) AS $$
DECLARE
    v_pin VARCHAR(4);
BEGIN
    LOOP
        -- Generate random 4-digit PIN (0000-9999)
        v_pin := LPAD((FLOOR(RANDOM() * 10000))::TEXT, 4, '0');
        -- Exit loop if PIN is unique
        EXIT WHEN NOT EXISTS (SELECT 1 FROM users WHERE rider_pin = v_pin);
    END LOOP;
    RETURN v_pin;
END;
$$ LANGUAGE plpgsql;

-- =========================================
-- 2. FUNCTION: Set Rider PIN (BEFORE INSERT)
-- =========================================
CREATE OR REPLACE FUNCTION trigger_set_rider_pin()
RETURNS TRIGGER AS $$
BEGIN
    -- Auto-generate unique 4-digit PIN for riders
    IF 'rider' = ANY(NEW.roles) THEN
        NEW.rider_pin := generate_unique_pin();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =========================================
-- 3. FUNCTION: Create User Dependents (AFTER INSERT)
-- =========================================
CREATE OR REPLACE FUNCTION trigger_create_user_dependents()
RETURNS TRIGGER AS $$
BEGIN
    -- Create wallet
    INSERT INTO wallets (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;

    -- Create Rider Profile
    IF 'rider' = ANY(NEW.roles) THEN
        INSERT INTO rider_profiles (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;
    END IF;
    
    -- Create Driver Profile
    IF 'driver' = ANY(NEW.roles) THEN
        INSERT INTO driver_profiles (user_id, first_name, last_name)
        VALUES (NEW.id, SPLIT_PART(COALESCE(NEW.name,''),' ',1), COALESCE(SPLIT_PART(NEW.name,' ',2), ''))
        ON CONFLICT (user_id) DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =========================================
-- 4. DROP OLD TRIGGERS
-- =========================================
DROP TRIGGER IF EXISTS create_user_dependents ON users;
DROP TRIGGER IF EXISTS set_rider_pin ON users;

-- =========================================
-- 5. CREATE NEW TRIGGERS (CORRECT ORDER)
-- =========================================

-- First: Set PIN (BEFORE INSERT)
-- This runs BEFORE the row is inserted, so we can modify NEW
CREATE TRIGGER set_rider_pin
BEFORE INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION trigger_set_rider_pin();

-- Second: Create Dependents (AFTER INSERT)
-- This runs AFTER the row is inserted, so NEW.id is available for foreign keys
CREATE TRIGGER create_user_dependents
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION trigger_create_user_dependents();

-- =========================================
-- 6. BACKFILL EXISTING USERS (Optional)
-- =========================================
-- Uncomment the following to generate PINs for existing users who don't have one

/*
UPDATE users
SET rider_pin = generate_unique_pin()
WHERE rider_pin IS NULL
  AND 'rider' = ANY(roles);
*/

-- =========================================
-- ✅ FIX COMPLETE
-- =========================================
