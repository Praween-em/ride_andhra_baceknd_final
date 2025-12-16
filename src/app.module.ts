import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ThrottlerModule } from '@nestjs/throttler';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { DriversModule } from './drivers/drivers.module';
import { RidesModule } from './rides/rides.module';
import { PaymentsModule } from './payments/payments.module';
import { NotificationsModule } from './notifications/notifications.module';
import { HealthModule } from './health/health.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRoot({
      type: 'postgres',
      url: process.env.DATABASE_URL,
      autoLoadEntities: true,
      synchronize: false, // Auto-create tables for the new database

      // Connection Pooling
      extra: {
        max: parseInt(process.env.DB_POOL_MAX || '10'), // Maximum connections
        min: parseInt(process.env.DB_POOL_MIN || '2'),  // Minimum connections
        idleTimeoutMillis: 30000, // Close idle connections after 30s
        connectionTimeoutMillis: 10000, // Timeout for acquiring connection

        // SSL Configuration
        ssl: (process.env.NODE_ENV === 'production' || process.env.DATABASE_URL?.includes('render.com')) ? {
          rejectUnauthorized: false,
        } : false,
      },

      // Query timeout
      connectTimeoutMS: 10000,

      // Logging
      logging: process.env.NODE_ENV === 'development' ? ['error', 'warn'] : ['error'],

      // Retry logic
      retryAttempts: 3,
      retryDelay: 3000,
    }),
    ThrottlerModule.forRoot([
      {
        ttl: 60000, // Time window in milliseconds (60 seconds)
        limit: 100, // Max requests per time window
      },
    ]),
    AuthModule,
    UsersModule,
    DriversModule,
    RidesModule,
    PaymentsModule,
    NotificationsModule,
    HealthModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule { }
