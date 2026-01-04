import { Controller, Patch, Param, Body, Get, UseGuards, Request } from '@nestjs/common';
import { UsersService } from './users.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { UpdateUserDto } from './dto/update-user.dto';

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) { }

  @UseGuards(JwtAuthGuard)
  @Patch(':id')
  update(@Param('id') id: string, @Body() updateUserDto: UpdateUserDto) {
    return this.usersService.update(id, updateUserDto.name);
  }

  @UseGuards(JwtAuthGuard)
  @Get('me')
  async getMe(@Request() req) {
    const userId = req.user.id;
    return this.usersService.findOneById(userId);
  }

  @UseGuards(JwtAuthGuard)
  @Get('rating')
  async getRating(@Request() req) {
    const userId = req.user.id;
    const rating = await this.usersService.getUserRating(userId);
    return { rating };
  }
}
