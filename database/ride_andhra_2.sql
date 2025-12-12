-- ===================================================================
-- RIDE ANDHRA — CONSOLIDATED DATABASE SCHEMA V2
-- ===================================================================
-- - Postgres + PostGIS
-- - Designed for Rider + Driver apps (compatible with both)
-- - Includes all migrations and fixes applied
-- - Multi-role support (users can be both rider and driver)
-- - MSG91 session support, tiered fares, rider PIN, secure docs
-- ===================================================================

-- =========================================
-- 0. EXTENSIONS
-- =========================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- for crypt() hashing

-- =========================================
-- 1. ENUM TYPES
-- =========================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role_enum') THEN
        CREATE TYPE user_role_enum AS ENUM ('rider','driver','admin');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'driver_status_enum') THEN
        CREATE TYPE driver_status_enum AS ENUM ('pending_approval','active','inactive','suspended');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ride_status_enum') THEN
        CREATE TYPE ride_status_enum AS ENUM ('pending','accepted','in_progress','completed','cancelled','no_drivers');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status_enum') THEN
        CREATE TYPE payment_status_enum AS ENUM ('pending','completed','failed','refunded');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method_enum') THEN
        CREATE TYPE payment_method_enum AS ENUM ('cash','card','wallet','upi');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'vehicle_type_enum') THEN
        CREATE TYPE vehicle_type_enum AS ENUM ('cab','bike','auto','bike_lite','parcel','premium');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transaction_type_enum') THEN
        CREATE TYPE transaction_type_enum AS ENUM ('ride_fare_credit','ride_fare_debit','payout','wallet_top_up','refund','cashback');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_type_enum') THEN
        CREATE TYPE notification_type_enum AS ENUM ('ride_request','ride_update','promotion','system','payment');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'document_status_enum') THEN
        CREATE TYPE document_status_enum AS ENUM ('pending','approved','rejected');
    END IF;
END$$;

-- =========================================
-- 2. CORE TABLES
-- =========================================

-- USERS: All users (rider, driver, admin) with multi-role support
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone_number VARCHAR(15) UNIQUE NOT NULL,
    name VARCHAR(150),
    email VARCHAR(254),
    -- 🔄 CHANGED: From single 'role' to 'roles' array for multi-role support
    roles user_role_enum[] NOT NULL DEFAULT ARRAY['rider'::user_role_enum],
    profile_image TEXT,
    is_verified BOOLEAN DEFAULT FALSE,
    is_blocked BOOLEAN DEFAULT FALSE,
    -- Rider PIN (hashed) - store salted hash only (crypt)
    rider_pin TEXT, -- 4 digit PIN for ride verification
    rider_pin_hash TEXT,
    rating_avg DECIMAL(3,2) DEFAULT 5.00,
    rating_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RIDER PROFILES
CREATE TABLE IF NOT EXISTS rider_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    rider_rating DECIMAL(3,2) DEFAULT 5.00,
    total_rides INTEGER DEFAULT 0,
    favorite_locations JSONB,
    pin_required BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- DRIVER PROFILES
CREATE TABLE IF NOT EXISTS driver_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    driver_rating DECIMAL(3,2) DEFAULT 5.00,
    total_rides INTEGER DEFAULT 0,
    earnings_total DECIMAL(12,2) DEFAULT 0.00,
    is_available BOOLEAN DEFAULT FALSE,
    is_online BOOLEAN DEFAULT FALSE,
    current_latitude DECIMAL(10,6),
    current_longitude DECIMAL(10,6),
    current_location GEOGRAPHY(Point,4326),
    current_address TEXT,
    status driver_status_enum DEFAULT 'pending_approval',
    vehicle_type vehicle_type_enum,
    vehicle_model VARCHAR(100),
    vehicle_color VARCHAR(30),
    vehicle_plate_number VARCHAR(50) UNIQUE,
    approved_at TIMESTAMPTZ,
    approved_by UUID REFERENCES users(id),
    document_submission_status VARCHAR(30) DEFAULT 'pending', -- 'pending','submitted','verified'
    background_check_passed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- DRIVER DOCUMENTS (metadata for secure storage)
CREATE TABLE IF NOT EXISTS driver_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES driver_profiles(user_id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL, -- 'license','aadhar','rc','insurance', etc.
    document_image TEXT, -- legacy/signed url fallback (deprecated, keep for compatibility)
    storage_provider VARCHAR(50), -- e.g., 's3','gcs'
    storage_path TEXT, -- object key or path
    checksum TEXT, -- sha256 hex
    is_encrypted BOOLEAN DEFAULT FALSE, -- true if stored encrypted
    access_policy JSONB, -- e.g., { "expires_at": "...", "read_only": true}
    document_number VARCHAR(100),
    expiry_date DATE,
    status document_status_enum DEFAULT 'pending',
    verified_by UUID REFERENCES users(id),
    verified_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(driver_id, document_type)
);

-- RIDES: Central ride table
CREATE TABLE IF NOT EXISTS rides (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rider_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    driver_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    pickup_latitude DECIMAL(10,6) NOT NULL,
    pickup_longitude DECIMAL(10,6) NOT NULL,
    pickup_location GEOGRAPHY(Point,4326) NOT NULL,
    pickup_address TEXT NOT NULL,
    dropoff_latitude DECIMAL(10,6) NOT NULL,
    dropoff_longitude DECIMAL(10,6) NOT NULL,
    dropoff_location GEOGRAPHY(Point,4326) NOT NULL,
    dropoff_address TEXT NOT NULL,
    vehicle_type vehicle_type_enum NOT NULL,
    estimated_distance_km DECIMAL(10,3),
    estimated_duration_min INTEGER,
    estimated_fare DECIMAL(12,2),
    actual_distance_km DECIMAL(10,3),
    actual_duration_min INTEGER,
    final_fare DECIMAL(12,2),
    status ride_status_enum DEFAULT 'pending',
    cancellation_reason TEXT,
    cancelled_by user_role_enum,
    rider_rating INTEGER CHECK (rider_rating BETWEEN 1 AND 5),
    driver_rating INTEGER CHECK (driver_rating BETWEEN 1 AND 5),
    rider_review TEXT,
    driver_review TEXT,
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    accepted_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    rider_pin_entered_by_driver BOOLEAN DEFAULT FALSE,
    rider_pin_verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- PAYMENTS
CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount DECIMAL(12,2) NOT NULL,
    currency VARCHAR(10) DEFAULT 'INR',
    payment_method payment_method_enum,
    transaction_id VARCHAR(200) UNIQUE,
    status payment_status_enum DEFAULT 'pending',
    gateway_response JSONB,
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- WALLETS
CREATE TABLE IF NOT EXISTS wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    balance DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(10) DEFAULT 'INR',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- TRANSACTIONS (wallet ledger)
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    ride_id UUID REFERENCES rides(id),
    payment_id UUID REFERENCES payments(id),
    amount DECIMAL(14,2) NOT NULL,
    type transaction_type_enum NOT NULL,
    description TEXT,
    balance_after DECIMAL(14,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- FARE_SETTINGS (base settings)
CREATE TABLE IF NOT EXISTS fare_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_type vehicle_type_enum UNIQUE NOT NULL,
    base_fare DECIMAL(12,2) NOT NULL,
    per_km_rate DECIMAL(10,4) NOT NULL,
    per_minute_rate DECIMAL(10,4) NOT NULL,
    minimum_fare DECIMAL(12,2) NOT NULL,
    surge_multiplier DECIMAL(6,3) DEFAULT 1.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- FARE TIERS (tiered per-km rates)
CREATE TABLE IF NOT EXISTS fare_tiers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_type vehicle_type_enum NOT NULL,
    km_from DECIMAL(10,3) NOT NULL, -- inclusive
    km_to DECIMAL(10,3) NOT NULL,   -- inclusive
    per_km_rate DECIMAL(10,4) NOT NULL, -- absolute per-km rate for this tier
    per_minute_rate DECIMAL(10,4) DEFAULT NULL,
    effective_from TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    CONSTRAINT fare_tiers_vehicle_fk FOREIGN KEY (vehicle_type) REFERENCES fare_settings(vehicle_type),
    CHECK (km_from >= 0 AND km_to >= km_from)
);

-- OTPs (deprecated but kept for compatibility)
CREATE TABLE IF NOT EXISTS otps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone_number VARCHAR(15) NOT NULL,
    otp_code VARCHAR(6) NOT NULL,
    purpose VARCHAR(50) DEFAULT 'login',
    is_verified BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- EXTERNAL AUTH SESSIONS (MSG91)
CREATE TABLE IF NOT EXISTS external_auth_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone_number VARCHAR(15) NOT NULL,
    provider VARCHAR(50) NOT NULL, -- e.g., 'msg91'
    provider_session_id TEXT, -- provider's session / request id
    provider_token TEXT, -- if provider returns a token (encrypt at app layer if sensitive)
    provider_token_expires_at TIMESTAMPTZ,
    provider_response JSONB,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- NOTIFICATIONS (in-app)
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ride_id UUID REFERENCES rides(id),
    type notification_type_enum NOT NULL,
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    data JSONB,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Notification preferences & queue (multi-channel + retries)
CREATE TABLE IF NOT EXISTS notification_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel VARCHAR(20) DEFAULT 'push', -- push,sms,email
    enabled BOOLEAN DEFAULT TRUE,
    types JSONB DEFAULT '[]'::jsonb, -- list of notification_type_enum values allowed
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, channel)
);

CREATE TABLE IF NOT EXISTS notification_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type notification_type_enum NOT NULL,
    payload JSONB NOT NULL,
    channel VARCHAR(20) DEFAULT 'push',
    attempt_count INTEGER DEFAULT 0,
    next_attempt_at TIMESTAMPTZ DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'pending', -- pending,sent,failed
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RIDE RATINGS
CREATE TABLE IF NOT EXISTS ride_ratings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    rater_user_id UUID NOT NULL REFERENCES users(id),
    rated_user_id UUID NOT NULL REFERENCES users(id),
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RIDER PIN ATTEMPTS (audit & anti-fraud)
CREATE TABLE IF NOT EXISTS rider_pin_attempts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    driver_id UUID,
    ride_id UUID,
    attempt_ts TIMESTAMPTZ DEFAULT NOW(),
    success BOOLEAN,
    ip_address VARCHAR(64),
    notes TEXT
);

-- =========================================
-- 3. DRIVER APP COMPATIBILITY LAYER (VIEWS + TRIGGERS)
-- =========================================

-- VIEW: driver_app_drivers (compatible with multi-role)
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
WHERE 'driver' = ANY(u.roles); -- 🔄 CHANGED: Check roles array instead of single role

-- VIEW: driver_app_rides
CREATE OR REPLACE VIEW driver_app_rides AS
SELECT
    r.id,
    r.rider_id,
    r.driver_id,
    r.pickup_location,
    r.dropoff_location,
    CASE
        WHEN r.status = 'pending' THEN 'requested'
        WHEN r.status = 'in_progress' THEN 'ongoing'
        ELSE r.status::text
    END AS status,
    COALESCE(r.final_fare, r.estimated_fare) AS fare,
    r.created_at,
    r.updated_at
FROM rides r;

-- Function: update driver_app_drivers
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

-- Function: update driver_app_rides
CREATE OR REPLACE FUNCTION handle_driver_app_rides_update()
RETURNS TRIGGER AS $$
DECLARE
    new_status ride_status_enum;
BEGIN
    SELECT CASE
        WHEN NEW.status = 'ongoing' THEN 'in_progress'::ride_status_enum
        WHEN NEW.status = 'requested' THEN 'pending'::ride_status_enum
        ELSE NEW.status::ride_status_enum
    END INTO new_status;

    UPDATE rides
    SET driver_id = NEW.driver_id,
        status = new_status,
        final_fare = NEW.fare,
        updated_at = NOW()
    WHERE id = OLD.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_instead_of_update_on_driver_app_rides ON driver_app_rides;
CREATE TRIGGER trg_instead_of_update_on_driver_app_rides
INSTEAD OF UPDATE ON driver_app_rides
FOR EACH ROW
EXECUTE FUNCTION handle_driver_app_rides_update();

-- =========================================
-- 4. TRIGGERS & AUTOMATION
-- =========================================

-- Timestamp trigger
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach timestamp trigger to many tables
DO $$
DECLARE t TEXT;
BEGIN
    FOR t IN SELECT unnest(ARRAY[
        'users','rider_profiles','driver_profiles','rides','payments','wallets',
        'fare_settings','driver_documents','external_auth_sessions','notifications',
        'notification_preferences','notification_queue','ride_ratings'
    ]) LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS set_%s_timestamp ON %s;', t, t);
        EXECUTE format('CREATE TRIGGER set_%s_timestamp BEFORE UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();', t, t);
    END LOOP;
END$$;

-- 🔄 FIXED: Create user dependents on insert (wallet + profiles) with roles array support
CREATE OR REPLACE FUNCTION trigger_create_user_dependents()
RETURNS TRIGGER AS $$
BEGIN
    -- Create wallet for every user
    INSERT INTO wallets (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;

    -- Create rider profile if user has 'rider' role
    IF 'rider' = ANY(NEW.roles) THEN
        INSERT INTO rider_profiles (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;
    END IF;
    
    -- Create driver profile if user has 'driver' role
    IF 'driver' = ANY(NEW.roles) THEN
        INSERT INTO driver_profiles (user_id, first_name, last_name)
        VALUES (NEW.id, SPLIT_PART(COALESCE(NEW.name,''),' ',1), COALESCE(SPLIT_PART(NEW.name,' ',2), ''))
        ON CONFLICT (user_id) DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS create_user_dependents ON users;
CREATE TRIGGER create_user_dependents
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION trigger_create_user_dependents();

-- Sync geography from lat/lon
CREATE OR REPLACE FUNCTION trigger_sync_geography()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'rides' THEN
        NEW.pickup_location := ST_SetSRID(ST_MakePoint(NEW.pickup_longitude, NEW.pickup_latitude), 4326);
        NEW.dropoff_location := ST_SetSRID(ST_MakePoint(NEW.dropoff_longitude, NEW.dropoff_latitude), 4326);
    ELSIF TG_TABLE_NAME = 'driver_profiles' THEN
        IF NEW.current_longitude IS NOT NULL AND NEW.current_latitude IS NOT NULL THEN
            NEW.current_location := ST_SetSRID(ST_MakePoint(NEW.current_longitude, NEW.current_latitude), 4326);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_ride_geography ON rides;
CREATE TRIGGER sync_ride_geography
BEFORE INSERT OR UPDATE ON rides
FOR EACH ROW
EXECUTE FUNCTION trigger_sync_geography();

DROP TRIGGER IF EXISTS sync_driver_geography ON driver_profiles;
CREATE TRIGGER sync_driver_geography
BEFORE INSERT OR UPDATE ON driver_profiles
FOR EACH ROW
EXECUTE FUNCTION trigger_sync_geography();

-- PIN generation helper function
CREATE OR REPLACE FUNCTION generate_unique_pin()
RETURNS TEXT AS $$
DECLARE
    new_pin TEXT;
BEGIN
    LOOP
        new_pin := LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
        EXIT WHEN NOT EXISTS (SELECT 1 FROM users WHERE rider_pin = new_pin);
    END LOOP;
    RETURN new_pin;
END;
$$ LANGUAGE plpgsql;

-- =========================================
-- 5. BUSINESS LOGIC FUNCTIONS
-- =========================================

-- Generate OTP (legacy; retained)
CREATE OR REPLACE FUNCTION generate_otp(p_phone_number VARCHAR, p_purpose VARCHAR DEFAULT 'login')
RETURNS TEXT AS $$
DECLARE
    v_otp_code TEXT := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
BEGIN
    UPDATE otps SET expires_at = NOW() - INTERVAL '1 second'
    WHERE phone_number = p_phone_number AND purpose = p_purpose AND is_verified = FALSE;

    INSERT INTO otps (phone_number, otp_code, purpose, expires_at)
    VALUES (p_phone_number, v_otp_code, p_purpose, NOW() + INTERVAL '5 minutes');

    RETURN v_otp_code;
END;
$$ LANGUAGE plpgsql;

-- Verify OTP (legacy; retained)
CREATE OR REPLACE FUNCTION verify_otp(p_phone_number VARCHAR, p_otp_code VARCHAR, p_purpose VARCHAR DEFAULT 'login')
RETURNS JSONB AS $$
DECLARE
    v_otp_record RECORD;
    v_user_record RECORD;
BEGIN
    SELECT id INTO v_otp_record FROM otps
    WHERE phone_number = p_phone_number
      AND otp_code = p_otp_code
      AND purpose = p_purpose
      AND expires_at > NOW()
      AND is_verified = FALSE
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Invalid or expired OTP.');
    END IF;

    UPDATE otps SET is_verified = TRUE WHERE id = v_otp_record.id;

    SELECT * INTO v_user_record FROM users WHERE phone_number = p_phone_number;

    IF FOUND THEN
        UPDATE users SET is_verified = TRUE WHERE id = v_user_record.id;
        RETURN jsonb_build_object('success', true, 'user_exists', true, 'user', row_to_json(v_user_record));
    ELSE
        RETURN jsonb_build_object('success', true, 'user_exists', false);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Calculate tiered fare
CREATE OR REPLACE FUNCTION calculate_fare_tiered(p_vehicle_type vehicle_type_enum, p_distance_km DECIMAL, p_duration_min INTEGER)
RETURNS JSONB AS $$
DECLARE
    v_base fare_settings%ROWTYPE;
    v_total DECIMAL := 0;
    v_minutes_component DECIMAL := 0;
    v_remaining DECIMAL := GREATEST(p_distance_km, 0);
    v_tier RECORD;
    v_distance_in_tier DECIMAL;
    v_estimated_fare DECIMAL;
BEGIN
    SELECT * INTO v_base FROM fare_settings WHERE vehicle_type = p_vehicle_type AND is_active = TRUE LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Fare settings not found for vehicle type: %', p_vehicle_type;
    END IF;

    v_total := v_total + v_base.base_fare;

    FOR v_tier IN
        SELECT * FROM fare_tiers WHERE vehicle_type = p_vehicle_type AND is_active = TRUE ORDER BY km_from
    LOOP
        IF v_remaining <= 0 THEN
            EXIT;
        END IF;

        -- Determine overlap of [km_from, km_to] with remaining distance
        IF p_distance_km <= v_tier.km_from THEN
            CONTINUE;
        END IF;

        v_distance_in_tier := LEAST(v_tier.km_to - v_tier.km_from + 0.0, v_remaining);
        IF v_distance_in_tier < 0 THEN
            CONTINUE;
        END IF;

        v_total := v_total + (v_distance_in_tier * v_tier.per_km_rate);
        IF v_tier.per_minute_rate IS NOT NULL THEN
            v_minutes_component := v_minutes_component + (p_duration_min * v_tier.per_minute_rate);
        END IF;
        v_remaining := v_remaining - v_distance_in_tier;
    END LOOP;

    IF v_remaining > 0 THEN
        v_total := v_total + (v_remaining * v_base.per_km_rate);
    END IF;

    IF v_minutes_component = 0 THEN
        v_minutes_component := p_duration_min * v_base.per_minute_rate;
    END IF;

    v_estimated_fare := v_total + v_minutes_component;
    IF v_estimated_fare < v_base.minimum_fare THEN
        v_estimated_fare := v_base.minimum_fare;
    END IF;

    v_estimated_fare := ROUND(v_estimated_fare * v_base.surge_multiplier::NUMERIC, 2);

    RETURN jsonb_build_object(
        'vehicle_type', p_vehicle_type,
        'distance_km', p_distance_km,
        'duration_min', p_duration_min,
        'fare', v_estimated_fare
    );
END;
$$ LANGUAGE plpgsql;

-- Create ride request: estimates fare, creates ride, notifies nearby drivers
CREATE OR REPLACE FUNCTION create_ride_request(
    p_rider_id UUID,
    p_pickup_lat DECIMAL, p_pickup_lon DECIMAL, p_pickup_addr TEXT,
    p_drop_lat DECIMAL, p_drop_lon DECIMAL, p_drop_addr TEXT,
    p_vehicle_type vehicle_type_enum
) RETURNS JSONB AS $$
DECLARE
    v_ride rides%ROWTYPE;
    v_est JSONB;
    v_est_fare DECIMAL;
    v_est_distance DECIMAL;
    v_est_duration INTEGER;
    v_pickup_geog GEOGRAPHY(Point,4326);
    v_drop_geog GEOGRAPHY( Point,4326);
    v_nearby_driver RECORD;
BEGIN
    SELECT ST_SetSRID(ST_MakePoint(p_pickup_lon, p_pickup_lat), 4326) INTO v_pickup_geog;
    SELECT ST_SetSRID(ST_MakePoint(p_drop_lon, p_drop_lat), 4326) INTO v_drop_geog;

    v_est_distance := ST_Distance(v_pickup_geog, v_drop_geog) / 1000.0;
    v_est_duration := GREATEST(5, CEIL(v_est_distance * 2.5))::INTEGER;

    v_est := calculate_fare_tiered(p_vehicle_type, v_est_distance, v_est_duration);
    v_est_fare := (v_est ->> 'fare')::DECIMAL;

    INSERT INTO rides (
        rider_id, vehicle_type,
        pickup_latitude, pickup_longitude, pickup_address, pickup_location,
        dropoff_latitude, dropoff_longitude, dropoff_address, dropoff_location,
        estimated_distance_km, estimated_duration_min, estimated_fare
    ) VALUES (
        p_rider_id, p_vehicle_type,
        p_pickup_lat, p_pickup_lon, p_pickup_addr, v_pickup_geog,
        p_drop_lat, p_drop_lon, p_drop_addr, v_drop_geog,
        v_est_distance, v_est_duration, v_est_fare
    ) RETURNING * INTO v_ride;

    -- Notify nearby drivers (e.g., 10 drivers within 5 km)
    FOR v_nearby_driver IN
        SELECT dp.user_id
        FROM driver_profiles dp
        WHERE dp.status = 'active'
          AND dp.is_online = TRUE
          AND dp.is_available = TRUE
          AND dp.vehicle_type = p_vehicle_type
          AND ST_DWithin(dp.current_location, v_pickup_geog, 5000)
        ORDER BY dp.current_location <-> v_pickup_geog
        LIMIT 10
    LOOP
        INSERT INTO notifications (user_id, ride_id, type, title, message, data)
        VALUES (
            v_nearby_driver.user_id,
            v_ride.id,
            'ride_request',
            'New Ride Request',
            'A rider nearby needs a ride. Tap to view details.',
            jsonb_build_object(
                'ride_id', v_ride.id,
                'rider_id', p_rider_id,
                'pickup_address', p_pickup_addr,
                'pickup_latitude', p_pickup_lat,
                'pickup_longitude', p_pickup_lon,
                'vehicle_type', p_vehicle_type,
                'estimated_fare', v_est_fare
            )
        );

        -- Optionally enqueue for SMS/push via notification_queue
        INSERT INTO notification_queue (user_id, type, payload, channel)
        VALUES (
            v_nearby_driver.user_id,
            'ride_request',
            jsonb_build_object(
                'ride_id', v_ride.id,
                'pickup_address', p_pickup_addr,
                'estimated_fare', v_est_fare
            ),
            'push'
        );
    END LOOP;

    RETURN jsonb_build_object('success', true, 'ride', row_to_json(v_ride));
END;
$$ LANGUAGE plpgsql;

-- Process a payment (wallet-based flow included)
CREATE OR REPLACE FUNCTION process_payment(p_payment_id UUID, p_method payment_method_enum, p_transaction_id VARCHAR DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    v_payment payments%ROWTYPE;
    v_ride rides%ROWTYPE;
    v_driver_wallet wallets%ROWTYPE;
    v_rider_wallet wallets%ROWTYPE;
    v_new_balance DECIMAL;
BEGIN
    SELECT * INTO v_payment FROM payments WHERE id = p_payment_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Payment not found.');
    END IF;
    IF v_payment.status = 'completed' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Payment already completed.');
    END IF;

    SELECT * INTO v_ride FROM rides WHERE id = v_payment.ride_id;

    IF p_method = 'wallet' THEN
        SELECT * INTO v_driver_wallet FROM wallets WHERE user_id = v_ride.driver_id;
        SELECT * INTO v_rider_wallet FROM wallets WHERE user_id = v_ride.rider_id;

        IF v_rider_wallet.balance < v_payment.amount THEN
            RETURN jsonb_build_object('success', false, 'message', 'Insufficient wallet balance.');
        END IF;

        UPDATE wallets SET balance = balance - v_payment.amount WHERE id = v_rider_wallet.id RETURNING balance INTO v_new_balance;
        INSERT INTO transactions (wallet_id, ride_id, payment_id, amount, type, description, balance_after)
        VALUES (v_rider_wallet.id, v_ride.id, v_payment.id, -v_payment.amount, 'ride_fare_debit', 'Paid for ride', v_new_balance);

        UPDATE wallets SET balance = balance + v_payment.amount WHERE id = v_driver_wallet.id RETURNING balance INTO v_new_balance;
        INSERT INTO transactions (wallet_id, ride_id, payment_id, amount, type, description, balance_after)
        VALUES (v_driver_wallet.id, v_ride.id, v_payment.id, v_payment.amount, 'ride_fare_credit', 'Credit for ride', v_new_balance);
    END IF;

    UPDATE payments
    SET status = 'completed', payment_method = p_method, transaction_id = p_transaction_id, paid_at = NOW(), updated_at = NOW()
    WHERE id = p_payment_id;

    UPDATE driver_profiles SET earnings_total = earnings_total + v_payment.amount WHERE user_id = v_ride.driver_id;

    RETURN jsonb_build_object('success', true, 'message', 'Payment processed successfully.');
END;
$$ LANGUAGE plpgsql;

-- Verify rider PIN: compares plain PIN (input) to stored rider_pin_hash using crypt()
CREATE OR REPLACE FUNCTION verify_rider_pin(p_rider_id UUID, p_pin TEXT, p_driver_id UUID DEFAULT NULL, p_ride_id UUID DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    v_hash TEXT;
    v_ok BOOLEAN;
BEGIN
    SELECT rider_pin_hash INTO v_hash FROM users WHERE id = p_rider_id;
    IF v_hash IS NULL OR v_hash = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Rider has no PIN set.');
    END IF;

    SELECT (v_hash = crypt(p_pin, v_hash)) INTO v_ok;
    INSERT INTO rider_pin_attempts (rider_id, driver_id, ride_id, success)
    VALUES (p_rider_id, p_driver_id, p_ride_id, v_ok);

    IF v_ok THEN
        UPDATE rides SET rider_pin_entered_by_driver = TRUE, rider_pin_verified_at = NOW(), updated_at = NOW()
        WHERE id = p_ride_id;
        RETURN jsonb_build_object('success', true, 'verified', true);
    ELSE
        RETURN jsonb_build_object('success', false, 'verified', false);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Register user convenience function (returns JSON)
CREATE OR REPLACE FUNCTION register_user(p_phone_number VARCHAR, p_name VARCHAR, p_role user_role_enum)
RETURNS JSONB AS $$
DECLARE
    v_user users%ROWTYPE;
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE phone_number = p_phone_number) THEN
        RETURN jsonb_build_object('success', false, 'message', 'User with this phone already exists.');
    END IF;

    INSERT INTO users (phone_number, name, roles, is_verified)
    VALUES (p_phone_number, p_name, ARRAY[p_role], true)
    RETURNING * INTO v_user;

    RETURN jsonb_build_object('success', true, 'user', row_to_json(v_user));
END;
$$ LANGUAGE plpgsql;

-- Update user PIN (store hashed PIN using crypt)
CREATE OR REPLACE FUNCTION set_rider_pin(p_user_id UUID, p_pin TEXT)
RETURNS JSONB AS $$
DECLARE
    v_hash TEXT;
BEGIN
    IF length(trim(p_pin)) <> 4 OR p_pin ~ '[^0-9]' THEN
        RETURN jsonb_build_object('success', false, 'message', 'PIN must be 4 digits.');
    END IF;

    v_hash := crypt(p_pin, gen_salt('bf', 8));
    UPDATE users SET rider_pin_hash = v_hash, updated_at = NOW() WHERE id = p_user_id;

    RETURN jsonb_build_object('success', true, 'message', 'PIN set.');
END;
$$ LANGUAGE plpgsql;

-- =========================================
-- 6. TRIGGERS FOR RATINGS AGGREGATION
-- =========================================

-- Update cached ratings when a new rating is inserted
CREATE OR REPLACE FUNCTION trg_update_user_rating_after_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_avg DECIMAL(3,2);
    v_count INTEGER;
BEGIN
    SELECT COUNT(*), ROUND(AVG(rating)::numeric,2) INTO v_count, v_avg FROM ride_ratings WHERE rated_user_id = NEW.rated_user_id;

    UPDATE users SET rating_avg = COALESCE(v_avg, 5.00), rating_count = COALESCE(v_count, 0) WHERE id = NEW.rated_user_id;

    IF EXISTS (SELECT 1 FROM driver_profiles WHERE user_id = NEW.rated_user_id) THEN
        UPDATE driver_profiles SET driver_rating = COALESCE(v_avg, 5.00) WHERE user_id = NEW.rated_user_id;
    END IF;

    IF EXISTS (SELECT 1 FROM rider_profiles WHERE user_id = NEW.rated_user_id) THEN
        UPDATE rider_profiles SET rider_rating = COALESCE(v_avg, 5.00) WHERE user_id = NEW.rated_user_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_after_insert_ride_ratings ON ride_ratings;
CREATE TRIGGER trg_after_insert_ride_ratings
AFTER INSERT ON ride_ratings
FOR EACH ROW
EXECUTE FUNCTION trg_update_user_rating_after_insert();

-- =========================================
-- 7. INDEXES (PERFORMANCE)
-- =========================================
CREATE INDEX IF NOT EXISTS idx_users_phone_number ON users(phone_number);
CREATE INDEX IF NOT EXISTS idx_users_roles ON users USING GIN(roles); -- GIN index for array queries
CREATE INDEX IF NOT EXISTS idx_driver_profiles_status ON driver_profiles(status, is_online, is_available);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_location ON driver_profiles USING GIST(current_location);
CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);
CREATE INDEX IF NOT EXISTS idx_rides_rider_id ON rides(rider_id);
CREATE INDEX IF NOT EXISTS idx_rides_driver_id ON rides(driver_id);
CREATE INDEX IF NOT EXISTS idx_rides_pickup_location ON rides USING GIST(pickup_location);
CREATE INDEX IF NOT EXISTS idx_rides_dropoff_location ON rides USING GIST(dropoff_location);
CREATE INDEX IF NOT EXISTS idx_payments_ride_id ON payments(ride_id);
CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_fare_tiers_vehicle ON fare_tiers(vehicle_type);

-- =========================================
-- 8. SAMPLE DATA (FARE SETTINGS)
-- =========================================
INSERT INTO fare_settings (vehicle_type, base_fare, per_km_rate, per_minute_rate, minimum_fare, surge_multiplier) VALUES
('cab', 40.00, 15.00, 2.00, 60.00, 1.00),
('bike', 20.00, 8.00, 1.00, 30.00, 1.00),
('auto', 30.00, 12.00, 1.50, 50.00, 1.00),
('bike_lite', 15.00, 6.00, 0.80, 20.00, 1.00),
('parcel', 60.00, 18.00, 0.00, 100.00, 1.00),
('premium', 80.00, 22.00, 3.00, 150.00, 1.00)
ON CONFLICT (vehicle_type) DO UPDATE SET
    base_fare = EXCLUDED.base_fare,
    per_km_rate = EXCLUDED.per_km_rate,
    per_minute_rate = EXCLUDED.per_minute_rate,
    minimum_fare = EXCLUDED.minimum_fare,
    surge_multiplier = EXCLUDED.surge_multiplier,
    updated_at = NOW();

-- =========================================
-- NOTES & PRODUCTION READINESS
-- =========================================
-- 1) ✅ Multi-role support: Users can be both rider and driver by having both roles in the array
-- 2) ✅ Fixed triggers: All triggers now use NEW.roles array instead of NEW.role
-- 3) ✅ Driver app compatibility: Views and triggers maintained for existing driver app
-- 4) ⚠️  Before deploying, back up existing database
-- 5) ⚠️  Configure object storage (S3/GCS) for driver_documents
-- 6) ⚠️  Set up API keys and secrets in environment variables
-- 7) ⚠️  Deploy background worker to process notification_queue
-- 8) ⚠️  Enable SSL/TLS for production database connections
