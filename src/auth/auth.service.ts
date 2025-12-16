import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { UsersService } from '../users/users.service';
import { User, UserRole } from '../users/user.entity';
import { Driver } from '../drivers/driver.entity';
import { LoggerService } from '../common/logger/logger.service';

interface JwtPayload {
  sub: string;
  phoneNumber: string;
  roles: UserRole[];
  name: string;
}

@Injectable()
export class AuthService {
  private readonly logger = new LoggerService();

  constructor(
    private readonly usersService: UsersService,
    private readonly jwtService: JwtService,
    @InjectRepository(Driver)
    private readonly driverRepository: Repository<Driver>,
  ) { }

  async sendOtp(phoneNumber: string): Promise<any> {
    this.logger.log(`Sending OTP to: ${phoneNumber}`, 'AuthService');
    const authKey = process.env.MSG91_AUTH_KEY;
    const templateId = process.env.MSG91_TEMPLATE_ID;

    if (!authKey || !templateId) {
      this.logger.warn('MSG91 credentials not found in environment variables', 'AuthService');
      return { message: 'OTP sending simulated (missing credentials)' };
    }

    try {
      const mobileForOtp = phoneNumber.length === 10 ? '91' + phoneNumber : phoneNumber;
      const url = `https://control.msg91.com/api/v5/otp?template_id=${templateId}&mobile=${mobileForOtp}&authkey=${authKey}`;
      const response = await fetch(url, { method: 'POST' });
      const data = await response.json();

      if (data.type === 'success') {
        return { message: 'OTP sent successfully', details: data };
      } else {
        throw new Error(data.message || 'Failed to send OTP');
      }
    } catch (error) {
      this.logger.error('Error sending OTP via MSG91', error instanceof Error ? error.stack : undefined, 'AuthService');
      throw new Error('Failed to send OTP');
    }
  }

  async verifyOtp(
    phoneNumber: string,
    otp: string,
  ): Promise<any> {
    const authKey = process.env.MSG91_AUTH_KEY;
    const isProduction = process.env.NODE_ENV === 'production';

    // 1. Explicit Test/App Review Credentials
    if (phoneNumber === '1234567890' && otp === '123456') {
      this.logger.log('Test credentials verified. Bypassing MSG91.', 'AuthService');
      return this.loginVerified(phoneNumber);
    }

    // 2. MSG91 Verification
    if (authKey) {
      try {
        const mobileForOtp = phoneNumber.length === 10 ? '91' + phoneNumber : phoneNumber;
        const maskedKey = authKey ? `${authKey.substring(0, 4)}...${authKey.substring(authKey.length - 4)}` : 'MISSING';
        this.logger.log(`Verifying OTP for ${mobileForOtp} with Key: ${maskedKey}`, 'AuthService');

        const url = `https://control.msg91.com/api/v5/otp/verify?otp=${otp}&mobile=${mobileForOtp}&authkey=${authKey}`;
        const response = await fetch(url, { method: 'GET' });
        const data = await response.json();
        this.logger.log(`MSG91 Verify Response: ${JSON.stringify(data)}`, 'AuthService');

        if (data.type !== 'success') {
          throw new UnauthorizedException(data.message || 'Invalid OTP');
        }
      } catch (error) {
        this.logger.error('Error verifying OTP via MSG91', error instanceof Error ? error.stack : undefined, 'AuthService');
        if (error instanceof UnauthorizedException) {
          throw error;
        }
        throw new UnauthorizedException('OTP verification failed');
      }
    } else {
      // 3. Missing Credentials Fallback
      if (isProduction) {
        this.logger.error('MSG91_AUTH_KEY is missing in PRODUCTION. Rejecting login.', undefined, 'AuthService');
        throw new UnauthorizedException('Service configuration error. Please contact support.');
      }

      this.logger.warn('MSG91_AUTH_KEY not set. Allowing ANY OTP for development.', 'AuthService');
      if (!otp) {
        throw new UnauthorizedException('Invalid OTP');
      }
    }

    return this.loginVerified(phoneNumber);
  }

  async loginVerified(phoneNumber: string): Promise<any> {
    const existingUser = await this.usersService.findOneByPhoneNumber(phoneNumber);

    let user: User;
    let isNewUser: boolean = false;

    if (existingUser) {
      user = existingUser;
    } else {
      user = await this.usersService.create({
        phone_number: phoneNumber,
        name: '',
        roles: [UserRole.RIDER],
      });
      isNewUser = true;
    }

    const payload: JwtPayload = {
      sub: user.id,
      phoneNumber: user.phone_number,
      roles: user.roles,
      name: user.name,
    };

    const accessToken = this.jwtService.sign(payload);

    // Check for driver profile
    const driver = await this.driverRepository.findOne({ where: { user_id: user.id } });

    return {
      accessToken,
      isNewUser,
      user: {
        id: user.id,
        phone_number: user.phone_number,
        name: user.name,
        roles: user.roles,
        is_verified: user.is_verified,
        is_driver: !!driver || user.roles.includes(UserRole.DRIVER),
        driver_status: driver?.status || null,
        driver_id: driver?.user_id || null,
      }
    };
  }
}
