import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
} from 'typeorm';
import { Wallet } from './wallet.entity';

export enum TransactionType {
  RIDE_FARE_CREDIT = 'ride_fare_credit',
  RIDE_FARE_DEBIT = 'ride_fare_debit',
  PAYOUT = 'payout',
  WALLET_TOP_UP = 'wallet_top_up',
  REFUND = 'refund',
  CASHBACK = 'cashback',
}

@Entity('transactions')
export class WalletTransaction {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid' })
  wallet_id: string;

  @ManyToOne(() => Wallet)
  @JoinColumn({ name: 'wallet_id' })
  wallet: Wallet;

  @Column({ type: 'uuid', nullable: true })
  ride_id: string;

  @Column({ type: 'uuid', nullable: true })
  payment_id: string;

  @Column('decimal', { precision: 14, scale: 2 })
  amount: number;

  @Column({
    type: 'enum',
    enum: TransactionType,
    enumName: 'transaction_type_enum',
  })
  type: TransactionType;



  @Column({ type: 'text', nullable: true })
  description: string;

  @Column('decimal', { precision: 10, scale: 2 })
  balance_after: number;

  @CreateDateColumn()
  created_at: Date;
}
