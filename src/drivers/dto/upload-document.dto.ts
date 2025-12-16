import { IsEnum, IsOptional, IsString, IsDateString } from 'class-validator';
import { DocumentType } from '../driver-document.entity';

export class UploadDocumentDto {
    @IsEnum(DocumentType)
    documentType: DocumentType;

    @IsOptional()
    @IsString()
    documentNumber?: string;

    @IsOptional()
    @IsDateString()
    expiryDate?: string;
}
