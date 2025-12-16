import {
  Entity,
  PrimaryGeneratedColumn,
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

@Entity('driver_profiles')
export class Driver {
  @PrimaryGeneratedColumn('uuid')
  user_id: string;

  @OneToOne(() => User)
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ name: 'first_name', nullable: true })
  firstName: string;

  @Column({ name: 'last_name', nullable: true })
  lastName: string;

  @Column({ nullable: true }) // Kept for backward compatibility if needed, but prefer specific fields
  license_number: string;

  @Column({ name: 'vehicle_model', nullable: true })
  vehicleModel: string;

  @Column({ name: 'vehicle_color', nullable: true })
  vehicleColor: string;

  @Column({ name: 'vehicle_plate_number', unique: true, nullable: true })
  vehiclePlateNumber: string;

  @Column({
    type: 'enum',
    enum: VehicleType,
    enumName: 'vehicle_type_enum',
    nullable: true,
  })
  vehicle_type: VehicleType;

  @Column({ default: false })
  is_online: boolean; // Kept matching original name for compatibility, or can map to isOnline

  @Column({ default: false, name: 'is_available' })
  isAvailable: boolean;

  @Column({ type: 'timestamp with time zone', nullable: true })
  last_seen_at: Date;

  @Column('decimal', { precision: 10, scale: 6, nullable: true })
  current_latitude: number;

  @Column('decimal', { precision: 10, scale: 6, nullable: true })
  current_longitude: number;

  @Column({ type: 'geography', spatialFeatureType: 'Point', srid: 4326, nullable: true })
  current_location: string;

  @OneToMany(() => DriverDocument, (document) => document.driver)
  documents: DriverDocument[];

  @Column({ name: 'driver_rating', type: 'decimal', precision: 3, scale: 2, default: 5.00 })
  driverRating: number;

  @Column({ name: 'total_rides', default: 0 })
  totalRides: number;

  @Column({ name: 'earnings_total', type: 'decimal', precision: 12, scale: 2, default: 0.00 })
  earningsTotal: number;

  @Column({ name: 'status', default: 'pending_approval' })
  status: string;

  @Column({ name: 'approved_at', type: 'timestamptz', nullable: true })
  approvedAt: Date;

  @Column({ name: 'approved_by', nullable: true })
  approvedBy: string;

  @CreateDateColumn()
  created_at: Date;

  @UpdateDateColumn()
  updated_at: Date;

  // Getters for compatibility if needed
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
