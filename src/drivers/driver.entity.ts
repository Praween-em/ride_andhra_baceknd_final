import {
  Entity,
  PrimaryColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  OneToOne,
  JoinColumn,
  OneToMany,
} from 'typeorm';
import { User } from '../users/user.entity';
import { VehicleType } from '../rides/ride.entity';
import { DriverDocument } from './driver-document.entity';

export enum DriverStatus {
  PENDING_APPROVAL = 'pending_approval',
  ACTIVE = 'active',
  INACTIVE = 'inactive',
  SUSPENDED = 'suspended',
}

@Entity('driver_profiles')
export class Driver {
  @PrimaryColumn('uuid')
  user_id: string;

  @OneToOne(() => User)
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ name: 'first_name', type: 'varchar', length: 50, nullable: true })
  firstName: string;

  @Column({ name: 'last_name', type: 'varchar', length: 50, nullable: true })
  lastName: string;

  @Column({ name: 'driver_rating', type: 'decimal', precision: 3, scale: 2, default: 5.00 })
  driverRating: number;

  @Column({ name: 'total_rides', type: 'integer', default: 0 })
  totalRides: number;

  @Column({ name: 'earnings_total', type: 'decimal', precision: 12, scale: 2, default: 0.00 })
  earningsTotal: number;

  @Column({ name: 'is_available', type: 'boolean', default: false })
  isAvailable: boolean;

  @Column({ name: 'is_online', type: 'boolean', default: false })
  is_online: boolean;

  @Column({ name: 'current_latitude', type: 'decimal', precision: 10, scale: 6, nullable: true })
  current_latitude: number;

  @Column({ name: 'current_longitude', type: 'decimal', precision: 10, scale: 6, nullable: true })
  current_longitude: number;

  @Column({ name: 'current_location', type: 'geography', spatialFeatureType: 'Point', srid: 4326, nullable: true })
  current_location: string;

  @Column({ name: 'current_address', type: 'text', nullable: true })
  current_address: string;

  @Column({
    name: 'status',
    type: 'enum',
    enum: DriverStatus,
    enumName: 'driver_status_enum',
    default: DriverStatus.PENDING_APPROVAL,
  })
  status: DriverStatus;

  @Column({
    name: 'vehicle_type',
    type: 'enum',
    enum: VehicleType,
    enumName: 'vehicle_type_enum',
    nullable: true,
  })
  vehicle_type: VehicleType;

  @Column({ name: 'vehicle_model', type: 'varchar', length: 100, nullable: true })
  vehicleModel: string;

  @Column({ name: 'vehicle_color', type: 'varchar', length: 30, nullable: true })
  vehicleColor: string;

  @Column({ name: 'vehicle_plate_number', type: 'varchar', length: 50, unique: true, nullable: true })
  vehiclePlateNumber: string;

  @Column({ name: 'approved_at', type: 'timestamptz', nullable: true })
  approvedAt: Date;

  @Column({ name: 'approved_by', type: 'uuid', nullable: true })
  approvedBy: string;

  @Column({ name: 'document_submission_status', type: 'varchar', length: 30, default: 'pending' })
  document_submission_status: string;

  @Column({ name: 'background_check_passed', type: 'boolean', default: false })
  background_check_passed: boolean;

  @OneToMany(() => DriverDocument, (document) => document.driver)
  documents: DriverDocument[];

  @CreateDateColumn({ name: 'created_at' })
  created_at: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updated_at: Date;

  // Getters for compatibility
  get isOnline(): boolean {
    return this.is_online;
  }

  set isOnline(value: boolean) {
    this.is_online = value;
  }

  get currentLatitude(): number {
    return this.current_latitude;
  }

  set currentLatitude(value: number) {
    this.current_latitude = value;
  }

  get currentLongitude(): number {
    return this.current_longitude;
  }

  set currentLongitude(value: number) {
    this.current_longitude = value;
  }
}
