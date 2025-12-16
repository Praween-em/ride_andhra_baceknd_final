import { IsString, IsNotEmpty, Length, Matches } from 'class-validator';

export class SendOtpDto {
    @IsString()
    @IsNotEmpty()
    @Length(10, 15) // Allow for country codes if needed, but min 10
    @Matches(/^\d+$/, { message: 'Phone number must contain only digits' })
    phoneNumber: string;
}

export class VerifyOtpDto {
    @IsString()
    @IsNotEmpty()
    @Length(10, 15)
    @Matches(/^\d+$/, { message: 'Phone number must contain only digits' })
    phoneNumber: string;

    @IsString()
    @IsNotEmpty()
    @Length(4, 6) // Allow 4 or 6 digit OTPs depending on config
    @Matches(/^\d+$/, { message: 'OTP must contain only digits' })
    otp: string;
}

export class LoginVerifiedDto {
    @IsString()
    @IsNotEmpty()
    @Length(10, 15)
    @Matches(/^\d+$/, { message: 'Phone number must contain only digits' })
    phoneNumber: string;
}
