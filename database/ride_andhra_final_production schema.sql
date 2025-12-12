-- ===================================================================
-- RIDE ANDHRA — FINAL PRODUCTION SCHEMA
-- ===================================================================
-- Generated for Render Deployment
-- Includes:
-- 1. Base Riders/Drivers structure
-- 2. Multi-role support (users.roles ARRAY)
-- 3. PostGIS Geography logic
-- 4. Bytea (BLOB) storage for Driver Documents (Migration 005)
-- 5. Tiered Fares & Wallet System
-- ===================================================================

-- =========================================
-- 0. EXTENSIONS & SETUP
-- =========================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

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
END$$;

-- =========================================
-- 2. CORE TABLES
-- =========================================

-- USERS: Multi-role support
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone_number VARCHAR(15) UNIQUE NOT NULL,
    name VARCHAR(150),
    email VARCHAR(254),
    roles user_role_enum[] NOT NULL DEFAULT ARRAY['rider'::user_role_enum], -- Array for multi-role
    profile_image TEXT,
    is_verified BOOLEAN DEFAULT FALSE,
    is_blocked BOOLEAN DEFAULT FALSE,
    rider_pin TEXT,      -- Store simple PIN for now as per current app logic
    rider_pin_hash TEXT, -- For future secure hashing
    push_token TEXT,     -- Added from migration 001
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
    document_submission_status VARCHAR(30) DEFAULT 'pending',
    background_check_passed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- DRIVER DOCUMENTS: BYTEA Storage (From Migration 005)
CREATE TABLE IF NOT EXISTS driver_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES driver_profiles(user_id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL,
    
    -- BLOB Storage
    document_image BYTEA NOT NULL,
    
    file_name VARCHAR(255),
    mime_type VARCHAR(100),
    file_size INTEGER,
    
    document_number VARCHAR(100),
    expiry_date DATE,
    status VARCHAR(20) DEFAULT 'pending',
    verified_by UUID REFERENCES users(id),
    verified_at TIMESTAMPTZ,
    rejection_reason TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT driver_documents_unique_type UNIQUE(driver_id, document_type),
    CONSTRAINT driver_documents_status_check CHECK (status IN ('pending', 'approved', 'rejected')),
    CONSTRAINT driver_documents_type_check CHECK (document_type IN ('profile_image', 'aadhar', 'license', 'pan', 'vehicle_rc', 'insurance'))
);

-- RIDES
CREATE TABLE IF NOT EXISTS rides (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rider_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    driver_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    pickup_latitude DECIMAL(10,6) NOT NULL,
    pickup_longitude DECIMAL(10,6) NOT NULL,
    pickup_location GEOGRAPHY(Point,4326) NOT NULL, -- Auto-synced via trigger
    pickup_address TEXT NOT NULL,
    dropoff_latitude DECIMAL(10,6) NOT NULL,
    dropoff_longitude DECIMAL(10,6) NOT NULL,
    dropoff_location GEOGRAPHY(Point,4326) NOT NULL, -- Auto-synced via trigger
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
    
    -- PIN Verification
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

-- TRANSACTIONS
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

-- FARE SETTINGS
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

-- FARE TIERS
CREATE TABLE IF NOT EXISTS fare_tiers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_type vehicle_type_enum NOT NULL,
    km_from DECIMAL(10,3) NOT NULL,
    km_to DECIMAL(10,3) NOT NULL,
    per_km_rate DECIMAL(10,4) NOT NULL,
    per_minute_rate DECIMAL(10,4) DEFAULT NULL,
    effective_from TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    CONSTRAINT fare_tiers_vehicle_fk FOREIGN KEY (vehicle_type) REFERENCES fare_settings(vehicle_type),
    CHECK (km_from >= 0 AND km_to >= km_from)
);

-- NOTIFICATIONS & QUEUE
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

CREATE TABLE IF NOT EXISTS notification_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type notification_type_enum NOT NULL,
    payload JSONB NOT NULL,
    channel VARCHAR(20) DEFAULT 'push',
    attempt_count INTEGER DEFAULT 0,
    next_attempt_at TIMESTAMPTZ DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RIDE REJECTIONS (For 'Next Driver' Logic)
CREATE TABLE IF NOT EXISTS ride_rejections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    driver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason TEXT,
    rejected_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(ride_id, driver_id)
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

-- OTPS (Legacy support)
CREATE TABLE IF NOT EXISTS otps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone_number VARCHAR(15) NOT NULL,
    otp_code VARCHAR(6) NOT NULL,
    purpose VARCHAR(50) DEFAULT 'login',
    is_verified BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =========================================
-- 3. VIEWS & COMPATIBILITY
-- =========================================

-- VIEW: driver_app_drivers
-- Used by Rider app to find nearby drivers easily
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

-- =========================================
-- 4. TRIGGERS & FUNCTIONS
-- =========================================

-- TIMESTAMP TRIGGER FUNCTION
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply Timestamp Trigger
DO $$
DECLARE t TEXT;
BEGIN
    FOR t IN SELECT unnest(ARRAY[
        'users','rider_profiles','driver_profiles','rides','payments','wallets',
        'fare_settings','driver_documents','notifications','ride_ratings'
    ]) LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS set_%s_timestamp ON %s;', t, t);
        EXECUTE format('CREATE TRIGGER set_%s_timestamp BEFORE UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION trigger_set_timestamp();', t, t);
    END LOOP;
END$$;

-- SYNC GEOGRAPHY FROM LAT/LON
-- Automatically updates the 'geography' columns when lat/lon changes
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

CREATE TRIGGER sync_ride_geography
BEFORE INSERT OR UPDATE ON rides
FOR EACH ROW
EXECUTE FUNCTION trigger_sync_geography();

CREATE TRIGGER sync_driver_geography
BEFORE INSERT OR UPDATE ON driver_profiles
FOR EACH ROW
EXECUTE FUNCTION trigger_sync_geography();

-- CREATE USER DEPENDENTS (Wallet, Profiles)
-- Creates necessary related records when a user is created
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

CREATE TRIGGER create_user_dependents
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION trigger_create_user_dependents();

-- =========================================
-- 5. HELPER FUNCTIONS
-- =========================================

-- TIERED FARE CALCULATION (Example)
CREATE OR REPLACE FUNCTION calculate_fare_tiered(p_vehicle_type vehicle_type_enum, p_distance_km DECIMAL, p_duration_min INTEGER)
RETURNS JSONB AS $$
DECLARE
    v_base fare_settings%ROWTYPE;
    v_total DECIMAL := 0;
    v_estimated_fare DECIMAL;
BEGIN
    -- Simplified logic for example; full tiered logic in application or expanded here
    SELECT * INTO v_base FROM fare_settings WHERE vehicle_type = p_vehicle_type AND is_active = TRUE LIMIT 1;
    IF NOT FOUND THEN
        -- Fallback default
        RETURN jsonb_build_object('fare', 0);
    END IF;

    v_total := v_base.base_fare + (p_distance_km * v_base.per_km_rate) + (p_duration_min * v_base.per_minute_rate);
    
    IF v_total < v_base.minimum_fare THEN
        v_total := v_base.minimum_fare;
    END IF;

    v_estimated_fare := ROUND(v_total * v_base.surge_multiplier::NUMERIC, 2);

    RETURN jsonb_build_object(
        'vehicle_type', p_vehicle_type,
        'distance_km', p_distance_km,
        'duration_min', p_duration_min,
        'fare', v_estimated_fare
    );
END;
$$ LANGUAGE plpgsql;

-- DATA SEEDING (Basic Fare Settings)
INSERT INTO fare_settings (vehicle_type, base_fare, per_km_rate, per_minute_rate, minimum_fare)
VALUES 
('bike', 15.00,6.00, 0.50, 25.00),
('auto', 30.00, 10.00, 1.50, 40.00),
('cab', 80.00, 12.00, 2.00, 80.00),
('bike_lite', 15.00, 6.00, 1.20, 25.00),
('parcel', 35.00, 6.00, 1.80, 45.00),
('premium', 50.00, 12.00, 2.00, 80.00)


ON CONFLICT (vehicle_type) DO NOTHING;
