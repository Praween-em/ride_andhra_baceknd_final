import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { UsersService } from '../users/users.service';
import { User, UserRole } from '../users/user.entity';
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
  ) { }

  async sendOtp(phoneNumber: string): Promise<any> {
    const authKey = process.env.MSG91_AUTH_KEY;
    const templateId = process.env.MSG91_TEMPLATE_ID;

    if (!authKey || !templateId) {
      this.logger.warn('MSG91 credentials not found in environment variables', 'AuthService');
      return { message: 'OTP sending simulated (missing credentials)' };
    }

    try {
      const url = `https://control.msg91.com/api/v5/otp?template_id=${templateId}&mobile=${phoneNumber}&authkey=${authKey}`;
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
  ): Promise<{ accessToken: string; isNewUser: boolean }> {
    const authKey = process.env.MSG91_AUTH_KEY;

    if (phoneNumber === '1234567890' && otp === '123456') {
      this.logger.log('Test credentials verified. Bypassing MSG91.', 'AuthService');
      // Skip MSG91 verification
    } else if (authKey) {
      try {
        const url = `https://control.msg91.com/api/v5/otp/verify?otp=${otp}&mobile=${phoneNumber}&authkey=${authKey}`;
        const response = await fetch(url, { method: 'GET' });
        const data = await response.json();

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
      this.logger.warn('MSG91_AUTH_KEY not set. Allowing ANY OTP for development.', 'AuthService');
      if (!otp) {
        throw new UnauthorizedException('Invalid OTP');
      }
    }

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
    return { accessToken, isNewUser };
  }
}
