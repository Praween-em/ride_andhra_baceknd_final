import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { RegisterDriverDto } from './dto/register-driver.dto';
import { UpdateDriverStatusDto } from './dto/update-status.dto';
import { UploadDocumentDto } from './dto/upload-document.dto';
import { VerifyDocumentDto } from './dto/verify-document.dto';
import { Driver, DriverStatus } from './driver.entity';
import { DriverDocument, DocumentType, DocumentStatus } from './driver-document.entity';
import { Ride } from '../rides/ride.entity';
import { User, UserRole } from '../users/user.entity';

// Define Interface for Multer File since types might be missing
export interface MulterFile {
    fieldname: string;
    originalname: string;
    encoding: string;
    mimetype: string;
    size: number;
    buffer: Buffer;
}

@Injectable()
export class DriversService {
    constructor(
        @InjectRepository(User)
        private readonly userRepository: Repository<User>,
        @InjectRepository(Driver)
        private readonly driverRepository: Repository<Driver>,
        @InjectRepository(DriverDocument)
        private readonly driverDocumentRepository: Repository<DriverDocument>,
        @InjectRepository(Ride)
        private readonly rideRepository: Repository<Ride>,
    ) { }

    async getEarnings(userId: string) {
        const driverId = userId;

        const today = new Date();
        today.setHours(0, 0, 0, 0);

        const weekStart = new Date();
        weekStart.setDate(today.getDate() - today.getDay());
        weekStart.setHours(0, 0, 0, 0);

        const monthStart = new Date();
        monthStart.setDate(1);
        monthStart.setHours(0, 0, 0, 0);

        const getEarningsForRange = async (start: Date, end: Date) => {
            const result = await this.rideRepository
                .createQueryBuilder('ride')
                .select('SUM(ride.final_fare)', 'total')
                .where('ride.driver_id = :driverId', { driverId })
                .andWhere('ride.status = :status', { status: 'completed' })
                .andWhere('ride.created_at >= :start', { start })
                .andWhere('ride.created_at <= :end', { end })
                .getRawOne();
            return parseFloat(result.total || '0');
        };

        const getDailyBreakdown = async (start: Date, days: number) => {
            const breakdown: number[] = [];
            for (let i = 0; i < days; i++) {
                const dayStart = new Date(start);
                dayStart.setDate(start.getDate() + i);
                const dayEnd = new Date(dayStart);
                dayEnd.setHours(23, 59, 59, 999);

                const amount = await getEarningsForRange(dayStart, dayEnd);
                breakdown.push(amount);
            }
            return breakdown;
        };

        const todayEarnings = await getEarningsForRange(today, new Date());
        const todayBreakdown = [0, 0, 0];

        const weekEarnings = await getEarningsForRange(weekStart, new Date());
        const weekBreakdown = await getDailyBreakdown(weekStart, 7);

        const monthEarnings = await getEarningsForRange(monthStart, new Date());
        const monthBreakdown = [0, 0, 0, 0];

        return {
            today: {
                amount: todayEarnings,
                labels: ['Morning', 'Afternoon', 'Evening'],
                datasets: [{ data: todayBreakdown }]
            },
            week: {
                amount: weekEarnings,
                labels: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
                datasets: [{ data: weekBreakdown }]
            },
            month: {
                amount: monthEarnings,
                labels: ['Week 1', 'Week 2', 'Week 3', 'Week 4'],
                datasets: [{ data: monthBreakdown }]
            }
        };
    }

    async getProfile(userId: string) {
        const user = await this.userRepository.findOne({ where: { id: userId } });
        if (!user) {
            throw new NotFoundException('User not found');
        }

        const driver = await this.driverRepository.findOne({ where: { user_id: userId } });

        let profileImageDoc: DriverDocument | null = null;
        if (driver) {
            profileImageDoc = await this.driverDocumentRepository.findOne({
                where: {
                    driverId: driver.user_id,
                    documentType: DocumentType.PROFILE_IMAGE
                },
                select: ['id']
            });
        }

        const avatarUrl = profileImageDoc ? `/drivers/documents/image/${profileImageDoc.id}` : null;

        return {
            id: user.id,
            name: user.name,
            phone_number: user.phone_number,
            roles: user.roles,
            is_verified: user.is_verified || false,
            driver_id: driver?.user_id || null,
            user_id: user.id,
            driver_status: driver?.status || null,
            message: 'Driver profile retrieved successfully',
            profile: {
                name: user.name,
                phoneNumber: user.phone_number,
                vehicle: driver ? `${driver.vehicleModel} (${driver.vehiclePlateNumber})` : 'Not Registered',
                vehicleModel: driver?.vehicleModel,
                vehiclePlateNumber: driver?.vehiclePlateNumber,
                rating: driver?.driverRating || 5.0,
                trips: driver?.totalRides || 0,
                memberSince: new Date(user.created_at).getFullYear().toString(),
                avatar: avatarUrl,
                isOnline: driver?.isOnline || false,
                isAvailable: driver?.isAvailable || false,
            }
        };
    }

    private normalizePhoneNumber(phoneNumber: string): string {
        const digitsOnly = phoneNumber.replace(/\D/g, '');
        if (digitsOnly.startsWith('91') && digitsOnly.length === 12) {
            return digitsOnly.substring(2);
        }
        if (digitsOnly.length === 10) {
            return digitsOnly;
        }
        return digitsOnly.slice(-10);
    }

    async registerDriver(
        registerDriverDto: RegisterDriverDto,
        files: {
            profilePhoto?: MulterFile[],
            licenseFrontPhoto?: MulterFile[],
            licenseBackPhoto?: MulterFile[],
            aadhaarPhoto?: MulterFile[],
            panPhoto?: MulterFile[]
        }
    ) {
        const { phoneNumber, name, licenseNumber, vehicleModel, vehicleColor, vehiclePlateNumber } = registerDriverDto;

        const normalizedPhone = this.normalizePhoneNumber(phoneNumber);

        let user = await this.userRepository.findOne({ where: { phone_number: normalizedPhone } });

        if (!user) {
            const newUser = this.userRepository.create({
                phone_number: normalizedPhone,
                name: name,
                roles: [UserRole.RIDER, UserRole.DRIVER],
            });
            user = await this.userRepository.save(newUser);
        } else {
            user.name = name;
            if (!user.roles.includes(UserRole.DRIVER)) {
                user.roles = [...user.roles, UserRole.DRIVER];
            }
            user = await this.userRepository.save(user);
        }

        let driver = await this.driverRepository.findOne({ where: { user_id: user.id } });

        if (!driver) {
            const newDriver = this.driverRepository.create({
                user_id: user.id,
                user: user,
                firstName: name.split(' ')[0],
                lastName: name.split(' ').slice(1).join(' ') || '',
                vehicleModel,
                vehicleColor,
                vehiclePlateNumber,
                status: DriverStatus.PENDING_APPROVAL,
            });
            driver = await this.driverRepository.save(newDriver);
        } else {
            driver.firstName = name.split(' ')[0];
            driver.lastName = name.split(' ').slice(1).join(' ') || '';
            driver.vehicleModel = vehicleModel;
            driver.vehicleColor = vehicleColor;
            driver.vehiclePlateNumber = vehiclePlateNumber;
            driver = await this.driverRepository.save(driver);
        }

        const documentsToCreate: Partial<DriverDocument>[] = [];

        const addDoc = (fileList: MulterFile[] | undefined, type: DocumentType, docNumber?: string) => {
            if (fileList && fileList.length > 0) {
                const file = fileList[0];
                documentsToCreate.push({
                    driverId: driver!.user_id,
                    documentType: type,
                    documentImage: file.buffer,
                    fileName: file.originalname,
                    mimeType: file.mimetype,
                    fileSize: file.size,
                    documentNumber: docNumber,
                    status: DocumentStatus.PENDING,
                });
            }
        };

        addDoc(files.profilePhoto, DocumentType.PROFILE_IMAGE);
        addDoc(files.licenseFrontPhoto, DocumentType.LICENSE, licenseNumber);
        addDoc(files.licenseBackPhoto, DocumentType.LICENSE_BACK, licenseNumber);
        addDoc(files.aadhaarPhoto, DocumentType.AADHAR);
        addDoc(files.panPhoto, DocumentType.PAN);

        if (documentsToCreate.length > 0) {
            await this.driverDocumentRepository.save(documentsToCreate as any);
        }

        return {
            message: 'Driver registered successfully. Awaiting admin verification.',
            driverId: driver!.user_id,
            userId: user.id,
            status: 'pending_approval'
        };
    }

    async updateDriverStatus(userId: string, updateDriverStatusDto: UpdateDriverStatusDto) {
        const driver = await this.driverRepository.findOne({ where: { user_id: userId } });

        if (!driver) {
            throw new NotFoundException('Driver not found');
        }

        driver.isOnline = updateDriverStatusDto.online;
        driver.isAvailable = updateDriverStatusDto.online;

        if (updateDriverStatusDto.location) {
            driver.currentLatitude = updateDriverStatusDto.location.latitude;
            driver.currentLongitude = updateDriverStatusDto.location.longitude;
            driver.current_location = `POINT(${updateDriverStatusDto.location.longitude} ${updateDriverStatusDto.location.latitude})`;
        }

        await this.driverRepository.save(driver);
        return { message: 'Driver status updated successfully' };
    }

    async uploadDocument(
        driverId: string,
        uploadDocumentDto: UploadDocumentDto,
        file: MulterFile
    ) {
        const driver = await this.driverRepository.findOne({ where: { user_id: driverId } });
        if (!driver) {
            throw new NotFoundException('Driver not found');
        }

        const existingDocument = await this.driverDocumentRepository.findOne({
            where: {
                driverId,
                documentType: uploadDocumentDto.documentType,
            },
        });

        if (existingDocument) {
            existingDocument.documentImage = file.buffer;
            existingDocument.fileName = file.originalname;
            existingDocument.mimeType = file.mimetype;
            existingDocument.fileSize = file.size;
            existingDocument.documentNumber = uploadDocumentDto.documentNumber;
            existingDocument.expiryDate = uploadDocumentDto.expiryDate ? new Date(uploadDocumentDto.expiryDate) : undefined;
            existingDocument.status = DocumentStatus.PENDING;

            await this.driverDocumentRepository.save(existingDocument);
            return { message: 'Document updated successfully', document: existingDocument };
        } else {
            const newDocument = this.driverDocumentRepository.create({
                driverId,
                documentType: uploadDocumentDto.documentType,
                documentImage: file.buffer,
                fileName: file.originalname,
                mimeType: file.mimetype,
                fileSize: file.size,
                documentNumber: uploadDocumentDto.documentNumber,
                expiryDate: uploadDocumentDto.expiryDate ? new Date(uploadDocumentDto.expiryDate) : undefined,
                status: DocumentStatus.PENDING,
            });

            const savedDocument = await this.driverDocumentRepository.save(newDocument);
            return { message: 'Document uploaded successfully', document: savedDocument };
        }
    }

    async getDriverDocuments(driverId: string) {
        return this.driverDocumentRepository.find({
            where: { driverId },
            order: { createdAt: 'DESC' },
        });
    }

    async getDocumentById(documentId: string) {
        return this.driverDocumentRepository.findOne({
            where: { id: documentId },
        });
    }
}
