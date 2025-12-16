import { IsEnum, IsOptional, IsString } from 'class-validator';
import { DocumentStatus } from '../driver-document.entity';

export class VerifyDocumentDto {
    @IsEnum(DocumentStatus)
    status: DocumentStatus;

    @IsOptional()
    @IsString()
    rejectionReason?: string;
}
