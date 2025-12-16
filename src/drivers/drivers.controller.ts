import { Controller, Get, Post, Body, Patch, UseInterceptors, UploadedFiles, UploadedFile, Put, Req, UseGuards, Param, Query, Res } from '@nestjs/common';
import { FileFieldsInterceptor, FileInterceptor } from '@nestjs/platform-express';
import { Response } from 'express';
import * as multer from 'multer';
import { DriversService } from './drivers.service';
import { RegisterDriverDto } from './dto/register-driver.dto';
import { UpdateDriverStatusDto } from './dto/update-status.dto';
import { UploadDocumentDto } from './dto/upload-document.dto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// Configure multer to use memory storage
const multerOptions = {
    storage: multer.memoryStorage(),
};

@UseGuards(JwtAuthGuard)
@Controller('profile')
export class DriversController {
    constructor(private readonly driversService: DriversService) { }

    @Get()
    getProfile(@Req() req) {
        return this.driversService.getProfile(req.user.id);
    }

    @Post('register-driver')
    @UseInterceptors(FileFieldsInterceptor([
        { name: 'profilePhoto', maxCount: 1 },
        { name: 'licenseFrontPhoto', maxCount: 1 },
        { name: 'licenseBackPhoto', maxCount: 1 },
        { name: 'aadhaarPhoto', maxCount: 1 },
        { name: 'panPhoto', maxCount: 1 },
    ], multerOptions))
    async registerDriver(
        @UploadedFiles() files: {
            profilePhoto?: any[],
            licenseFrontPhoto?: any[],
            licenseBackPhoto?: any[],
            aadhaarPhoto?: any[],
            panPhoto?: any[]
        },
        @Body() registerDriverDto: RegisterDriverDto
    ) {
        return this.driversService.registerDriver(registerDriverDto, files);
    }

    @Put('driver/status')
    async updateDriverStatus(@Body() updateDriverStatusDto: UpdateDriverStatusDto, @Req() req) {
        const userId = req.user.id;
        return this.driversService.updateDriverStatus(userId, updateDriverStatusDto);
    }

    @Get('earnings')
    async getEarnings(@Req() req) {
        const userId = req.user.id;
        return this.driversService.getEarnings(userId);
    }

    // Document Management

    @Post('documents/:driverId')
    @UseInterceptors(FileInterceptor('document', multerOptions))
    async uploadDocument(
        @Param('driverId') driverId: string,
        @Body() uploadDocumentDto: UploadDocumentDto,
        @UploadedFile() file: any
    ) {
        return this.driversService.uploadDocument(driverId, uploadDocumentDto, file);
    }

    @Get('documents/image/:documentId')
    async getDocumentImage(
        @Param('documentId') documentId: string,
        @Res() res: any
    ) {
        const document = await this.driversService.getDocumentById(documentId);

        if (!document || !document.documentImage) {
            return res.status(404).json({ message: 'Document image not found' });
        }

        res.setHeader('Content-Type', document.mimeType || 'image/jpeg');
        res.setHeader('Content-Length', document.fileSize || document.documentImage.length);
        res.setHeader('Content-Disposition', `inline; filename="${document.fileName || 'document.jpg'}"`);
        res.send(document.documentImage);
    }

    @Get('documents/:driverId')
    async getDriverDocuments(@Param('driverId') driverId: string) {
        return this.driversService.getDriverDocuments(driverId);
    }
}
