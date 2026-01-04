import { IsNumber, IsString, IsNotEmpty, IsOptional } from 'class-validator';

export class CreateRideDto {
  @IsNumber()
  @IsOptional()
  pickup_latitude?: number;

  @IsNumber()
  @IsOptional()
  pickupLatitude?: number;

  @IsNumber()
  @IsOptional()
  pickup_longitude?: number;

  @IsNumber()
  @IsOptional()
  pickupLongitude?: number;

  @IsString()
  @IsOptional()
  pickup_address?: string;

  @IsString()
  @IsOptional()
  pickupLocation?: string;

  @IsNumber()
  @IsOptional()
  dropoff_latitude?: number;

  @IsNumber()
  @IsOptional()
  dropoffLatitude?: number;

  @IsNumber()
  @IsOptional()
  dropoff_longitude?: number;

  @IsNumber()
  @IsOptional()
  dropoffLongitude?: number;

  @IsString()
  @IsOptional()
  dropoff_address?: string;

  @IsString()
  @IsOptional()
  dropoffLocation?: string;

  @IsNumber()
  @IsOptional()
  fare?: number;

  @IsNumber()
  @IsOptional()
  distance?: number;

  @IsNumber()
  @IsOptional()
  duration?: number;

  @IsString()
  @IsOptional()
  vehicle_type?: string;

  @IsString()
  @IsOptional()
  vehicleType?: string;
}
