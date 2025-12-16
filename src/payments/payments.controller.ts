import { Controller, Get, UseGuards, Request } from '@nestjs/common';
import { PaymentsService } from './payments.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@Controller('payments')
export class PaymentsController {
    constructor(private readonly paymentsService: PaymentsService) { }

    @UseGuards(JwtAuthGuard)
    @Get('wallet')
    async getWallet(@Request() req) {
        const userId = req.user.id;
        const wallet = await this.paymentsService.getWalletByUserId(userId);
        return {
            balance: Number(wallet.balance),
            currency: wallet.currency,
            is_active: wallet.is_active,
        };
    }

    @UseGuards(JwtAuthGuard)
    @Get('wallet/transactions')
    async getWalletTransactions(@Request() req) {
        const userId = req.user.id;
        const transactions = await this.paymentsService.getWalletTransactions(userId, 10);

        return transactions.map(transaction => ({
            id: transaction.id,
            type: transaction.type,
            amount: Number(transaction.amount),
            description: transaction.description || 'Transaction',
            date: transaction.created_at.toISOString().split('T')[0],
            balance_after: Number(transaction.balance_after),
        }));
    }
}
