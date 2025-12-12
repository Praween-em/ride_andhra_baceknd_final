import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User, UserRole } from './user.entity';
import { RiderProfile } from './rider-profile.entity';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
    @InjectRepository(RiderProfile)
    private riderProfileRepository: Repository<RiderProfile>,
  ) { }

  async findOneByPhoneNumber(phoneNumber: string): Promise<User | null> {
    return this.usersRepository.findOne({
      where: { phone_number: phoneNumber },
    });
  }

  async create(userData: Partial<User>): Promise<User> {
    const user = this.usersRepository.create(userData);
    const savedUser = await this.usersRepository.save(user);

    // Create rider profile for new user if they have the RIDER role
    if (savedUser.roles?.includes(UserRole.RIDER)) {
      await this.createRiderProfile(savedUser.id);
    }

    return savedUser;
  }

  async update(id: string, name: string): Promise<User> {
    const user = await this.usersRepository.findOne({ where: { id } });
    if (!user) {
      throw new Error('User not found');
    }
    user.name = name;
    return this.usersRepository.save(user);
  }

  async createRiderProfile(userId: string): Promise<RiderProfile> {
    const riderProfile = this.riderProfileRepository.create({
      user_id: userId,
      rider_rating: 5.0,
      total_rides: 0,
    });
    return this.riderProfileRepository.save(riderProfile);
  }

  async getUserRating(userId: string): Promise<number> {
    const riderProfile = await this.riderProfileRepository.findOne({
      where: { user_id: userId },
    });

    if (!riderProfile) {
      // Create profile if it doesn't exist and return default rating
      await this.createRiderProfile(userId);
      return 5.0;
    }

    return Number(riderProfile.rider_rating);
  }
}
