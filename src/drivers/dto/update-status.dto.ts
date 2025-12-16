import { IsBoolean, IsLatitude, IsLongitude, IsObject, ValidateNested, IsOptional } from 'class-validator';
import { Type } from 'class-transformer';

class LocationDto {
    @IsLatitude()
    latitude: number;

    @IsLongitude()
    longitude: number;
}

export class UpdateDriverStatusDto {
    @IsBoolean()
    online: boolean;

    @IsOptional()
    @IsObject()
    @ValidateNested()
    @Type(() => LocationDto)
    location: LocationDto;
}
