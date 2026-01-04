import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Ride, RideStatus, VehicleType } from './ride.entity';
import { CreateRideDto } from './dto/create-ride.dto';
import { FareSetting } from './fare-setting.entity';
import { NotificationsService } from '../notifications/notifications.service';

@Injectable()
export class RidesService {
  constructor(
    @InjectRepository(Ride)
    private ridesRepository: Repository<Ride>,
    @InjectRepository(FareSetting)
    private fareSettingsRepository: Repository<FareSetting>,
    private notificationsService: NotificationsService,
  ) { }

  async calculateFare(
    distanceMeters: number,
    durationSeconds: number,
    vehicleType: VehicleType,
  ): Promise<{ fare: number }> {
    const distanceInKm = distanceMeters / 1000;
    const durationInMinutes = durationSeconds / 60;

    console.log(`[CalculateFare] Start: ${vehicleType}, RawDist: ${distanceMeters}m, RawDur: ${durationSeconds}s`);
    console.log(`[CalculateFare] Converted: Dist: ${distanceInKm.toFixed(3)}km, Dur: ${durationInMinutes.toFixed(2)}min`);

    const fareSetting = await this.fareSettingsRepository.findOne({
      where: { vehicle_type: vehicleType, is_active: true },
      relations: ['tiers'],
    });

    if (!fareSetting) {
      throw new NotFoundException(
        `Fare settings for vehicle type ${vehicleType} not found.`,
      );
    }
    console.log(`[CalculateFare] Found settings:`, fareSetting);

    // Defensively parse all values to numbers to avoid NaN issues
    const baseFare = parseFloat(fareSetting.base_fare as any);
    const perMinuteRate = parseFloat(fareSetting.per_minute_rate as any);
    const minimumFare = parseFloat(fareSetting.minimum_fare as any);
    const surgeMultiplier = parseFloat(fareSetting.surge_multiplier as any);
    const basePerKmRate = parseFloat(fareSetting.per_km_rate as any);

    let distanceCost = 0;
    let remainingDistance = distanceInKm;

    console.log(`[CalculateFare] Checking tiers for vehicle type: ${vehicleType}`);
    if (fareSetting.tiers && fareSetting.tiers.length > 0) {
      const sortedTiers = fareSetting.tiers.sort(
        (a, b) => parseFloat(a.km_from as any) - parseFloat(b.km_from as any),
      );
      console.log(`[CalculateFare] Found ${sortedTiers.length} tiers`);

      for (const tier of sortedTiers) {
        if (remainingDistance <= 0) break;

        const tierStartKm = parseFloat(tier.km_from as any);
        const tierEndKm = parseFloat(tier.km_to as any);
        const tierPerKmRate = parseFloat(tier.per_km_rate as any);

        const distanceInTierRange = tierEndKm - tierStartKm;
        const distanceToBillInTier = Math.min(
          remainingDistance,
          distanceInTierRange,
        );

        if (distanceToBillInTier > 0) {
          distanceCost += distanceToBillInTier * tierPerKmRate;
          remainingDistance -= distanceToBillInTier;
        }
      }
    }

    if (remainingDistance > 0) {
      distanceCost += remainingDistance * basePerKmRate;
    }

    const timeCost = durationInMinutes * perMinuteRate;

    let calculatedFare = baseFare + distanceCost + timeCost;

    calculatedFare = Math.max(calculatedFare, minimumFare);

    const finalFare = calculatedFare * surgeMultiplier;

    // Check for NaN, which becomes null when stringified in JSON
    if (isNaN(finalFare)) {
      console.error('Fare calculation resulted in NaN.', {
        vehicleType,
        distanceInKm,
        durationInMinutes,
        fareSetting,
      });
      // Throw an error to avoid returning a null fare, which crashes the frontend
      throw new Error('Fare calculation failed and resulted in a non-numeric value.');
    }

    console.log(`[CalculateFare] Final Fare: ${finalFare.toFixed(2)}`);
    return { fare: parseFloat(finalFare.toFixed(2)) };
  }

  async getMyRides(userId: string): Promise<Ride[]> {
    return this.ridesRepository.find({
      where: { rider_id: userId },
      relations: ['driver'],
    });
  }

  async getRideById(rideId: string): Promise<Ride | null> {
    return this.ridesRepository.findOne({
      where: { id: rideId },
      relations: ['driver'],
    });
  }

  async createRide(
    createRideDto: CreateRideDto & { rider_id: string },
  ): Promise<Ride> {
    console.log('--- [CreateRide] Start ---');
    console.log('Incoming DTO:', JSON.stringify(createRideDto, null, 2));

    // Normalize vehicle_type: lowercase and replace hyphens with underscores
    const vehicleTypeStr = createRideDto.vehicle_type || createRideDto.vehicleType;
    const normalizedVehicleType = vehicleTypeStr
      ?.toLowerCase()
      .replace(/-/g, '_') as VehicleType;

    const distanceRaw = createRideDto.distance || 0;
    const durationRaw = createRideDto.duration || 0;
    const distanceInKm = distanceRaw / 1000;
    const durationInMinutes = Math.ceil(durationRaw / 60);

    const rideToCreate: Partial<Ride> = {
      rider_id: createRideDto.rider_id,
      pickup_latitude: createRideDto.pickup_latitude || createRideDto.pickupLatitude,
      pickup_longitude: createRideDto.pickup_longitude || createRideDto.pickupLongitude,
      pickup_address: createRideDto.pickup_address || createRideDto.pickupLocation,
      dropoff_latitude: createRideDto.dropoff_latitude || createRideDto.dropoffLatitude,
      dropoff_longitude: createRideDto.dropoff_longitude || createRideDto.dropoffLongitude,
      dropoff_address: createRideDto.dropoff_address || createRideDto.dropoffLocation,
      vehicle_type: normalizedVehicleType,
      estimated_distance_km: distanceInKm,
      estimated_duration_min: durationInMinutes,
      estimated_fare: createRideDto.fare,
      status: RideStatus.PENDING,
    };

    console.log('Mapped Ride for creation:', JSON.stringify(rideToCreate, null, 2));

    try {
      const ride = this.ridesRepository.create(rideToCreate);
      const newRide = await this.ridesRepository.save(ride);
      console.log('--- [CreateRide] Success ---', newRide.id);

      this.notificationsService.sendRideUpdate(
        newRide.id,
        RideStatus.PENDING,
        newRide,
      );
      return newRide;
    } catch (error) {
      console.error('--- [CreateRide] ERROR ---');
      console.error(error);
      throw error;
    }
  }

  async updateRideStatus(
    rideId: string,
    status: RideStatus,
  ): Promise<Ride | null> {
    const ride = await this.getRideById(rideId);
    if (!ride) {
      return null;
    }
    ride.status = status;
    const updatedRide = await this.ridesRepository.save(ride);
    console.log('Ride status updated:', updatedRide.status);
    this.notificationsService.sendRideUpdate(rideId, status, updatedRide);
    return updatedRide;
  }

  async acceptRide(rideId: string, driverId: string): Promise<Ride | null> {
    const ride = await this.getRideById(rideId);
    if (!ride) {
      return null;
    }
    ride.driver_id = driverId;
    ride.status = RideStatus.ACCEPTED;
    const updatedRide = await this.ridesRepository.save(ride);
    this.notificationsService.sendRideUpdate(
      rideId,
      RideStatus.ACCEPTED,
      updatedRide,
    );
    return updatedRide;
  }

  async cancelRide(rideId: string): Promise<Ride | null> {
    return this.updateRideStatus(rideId, RideStatus.CANCELLED);
  }
}
