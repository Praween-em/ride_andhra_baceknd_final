import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { Driver } from './driver.entity';
import { User } from '../users/user.entity';

export enum DocumentType {
  PROFILE_IMAGE = 'profile_image',
  AADHAR = 'aadhar',
  LICENSE = 'license',
  LICENSE_BACK = 'license_back',
  PAN = 'pan',
  VEHICLE_RC = 'vehicle_rc',
  INSURANCE = 'insurance',
}

export enum DocumentStatus {
  PENDING = 'pending',
  APPROVED = 'approved',
  REJECTED = 'rejected',
}

@Entity('driver_documents')
export class DriverDocument {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'driver_id', type: 'uuid' })
  driverId: string;

  @ManyToOne(() => Driver, (driver) => driver.documents)
  @JoinColumn({ name: 'driver_id' })
  driver: Driver;

  @Column({
    type: 'varchar',
    length: 50,
    name: 'document_type',
  })
  documentType: DocumentType;

  @Column({ type: 'bytea', name: 'document_image' })
  documentImage: Buffer;

  @Column({ type: 'varchar', length: 255, nullable: true, name: 'file_name' })
  fileName?: string;

  @Column({ type: 'varchar', length: 100, nullable: true, name: 'mime_type' })
  mimeType?: string;

  @Column({ type: 'integer', nullable: true, name: 'file_size' })
  fileSize?: number;

  @Column({ type: 'varchar', length: 100, nullable: true, name: 'document_number' })
  documentNumber?: string;

  @Column({ type: 'date', nullable: true, name: 'expiry_date' })
  expiryDate?: Date;

  @Column({
    type: 'varchar',
    length: 20,
    default: DocumentStatus.PENDING,
  })
  status: DocumentStatus;

  @Column({ type: 'uuid', nullable: true, name: 'verified_by' })
  verifiedBy?: string;

  @ManyToOne(() => User, { nullable: true })
  @JoinColumn({ name: 'verified_by' })
  verifier?: User;

  @Column({ type: 'timestamptz', nullable: true, name: 'verified_at' })
  verifiedAt?: Date;

  @Column({ type: 'text', nullable: true, name: 'rejection_reason' })
  rejectionReason?: string;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}