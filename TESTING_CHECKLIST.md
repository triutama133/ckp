# Testing Checklist - Catatan Keuangan Pintar

## 🔐 Authentication & Supabase Sync

### Login & Register
- [ ] **Login dengan Email/Password**
  - Test dengan kredensial yang benar
  - Test dengan kredensial yang salah
  - Verifikasi error messages yang jelas
  
- [ ] **Register Akun Baru**
  - Test pendaftaran dengan data valid
  - Test validasi email format
  - Test password minimum length
  - Cek email verification (jika enabled di Supabase)

- [ ] **Login dengan Google**
  - Test Google Sign-In flow
  - Verifikasi user profile data tersimpan
  - Test cancel di middle of flow

- [ ] **Logout**
  - Test logout functionality
  - Verifikasi redirect ke login screen
  - Cek session cleared properly

### Supabase Data Sync
- [ ] **Initial Sync setelah Login**
  - Data transactions tersync dari Supabase
  - Data categories, accounts, groups tersync
  - Local database ter-update dengan data cloud

- [ ] **Real-time Sync**
  - Buat transaksi baru → cek tersync ke Supabase
  - Edit transaksi → cek update tersync
  - Delete transaksi → cek soft delete tersync
  - Test dengan koneksi internet ON/OFF

- [ ] **Offline Mode**
  - Matikan internet
  - Buat beberapa transaksi
  - Nyalakan internet kembali
  - Verifikasi semua transaksi tersync ke cloud

---

## 📊 Dashboard Features

### Portfolio Display
- [ ] **Total Portfolio Calculation**
  - Verifikasi formula: `totalBalance + saving + investment + totalGoldValue`
  - Cek tidak ada nilai 0 jika ada balance
  - Test dengan berbagai kombinasi (ada emas, tidak ada emas, dll)

- [ ] **Quick Stats Grid**
  - Pendapatan bulan ini
  - Pengeluaran bulan ini
  - Tabungan bulan ini
  - Investasi bulan ini

### Group/Personal Filter
- [ ] **Filter Personal**
  - Tampilkan hanya data personal
  - Portfolio hanya hitung data personal

- [ ] **Filter Grup**
  - Pilih grup tertentu
  - Tampilkan hanya data grup tersebut
  - Portfolio hitung data grup

### Period Selection
- [ ] **Template Periods**
  - Hari Ini
  - Minggu Ini
  - Bulan Ini
  - Tahun Ini
  - Custom Range

- [ ] **Custom Date Range**
  - Pilih start date dan end date
  - Verifikasi data filtered correctly

### Comparison Features (NEW! ✨)
- [ ] **Period-over-Period Comparison**
  - Lihat perbandingan dengan periode sebelumnya
  - Income comparison dengan % change
  - Expense comparison dengan % change
  - Saving comparison dengan % change
  - Visual indicators (up/down arrows)

### Smart Insights (ENHANCED! ✨)
- [ ] **50/30/20 Rule Insight**
  - Verifikasi calculation: 50% needs, 30% wants, 20% savings
  - Cek threshold warnings

- [ ] **Emergency Fund Assessment**
  - Calculation: balance / monthly expense
  - Target: 3-6 months
  - Color coding (red < 3 months, blue 3-6, green > 6)

- [ ] **Savings Rate Standard**
  - Percentage calculation
  - International benchmark (10-20%)
  - Encouragement messages

- [ ] **Period Comparison Insights**
  - Income trend (naik/turun)
  - Expense trend (naik/turun)
  - Saving trend

- [ ] **Top Category Analysis**
  - Largest spending category
  - Percentage of total expense

### Navigation
- [ ] **Transaction History Shortcut**
  - Button visible di dashboard
  - Navigasi ke transaction history screen
  - Kembali ke dashboard

---

## 💰 Transaction Management

### Manual Transaction Entry
- [ ] **Category Search Dropdown** (ENHANCED! ✨)
  - Open dropdown
  - Type to search categories
  - Select category

- [ ] **Account Selection dengan Savings** (NEW! ✨)
  - Lihat daftar accounts regular (Bank, Cash, E-wallet)
  - Lihat daftar savings accounts (Tabungan: [Goal Name])
  - Select savings account
  - Create transaction → verifikasi deduct dari savings

- [ ] **Transaction Types**
  - Income
  - Expense
  - Saving
  - Investment

- [ ] **Date Selection**
  - Pilih tanggal custom
  - Default to today

- [ ] **Amount Input**
  - Format currency correctly
  - Handle large numbers

### Chat-based Transaction (Parser)
- [ ] **Basic Parsing**
  - Income: "terima gaji 5juta"
  - Expense: "beli makan 50rb"
  - Saving: "nabung 1jt"
  - Investment: "beli saham 2jt"

- [ ] **Account Detection** (ENHANCED! ✨)
  - "bayar dari BCA 100rb"
  - "pakai GoPay 50rb"
  - "lewat Dana 200rb"
  - "dari Tabungan: Liburan 500rb" (NEW!)

- [ ] **Category Auto-detect**
  - Makan/makanan → Makanan & Minuman
  - Transport/gojek → Transportasi
  - Etc.

### Transaction History
- [ ] **Group/Personal Filter** (NEW! ✨)
  - "Semua" → tampilkan all transactions
  - "Personal" → hanya personal transactions
  - Grup specific → hanya grup transactions

- [ ] **Date Range Filter with Templates** (ENHANCED! ✨)
  - Hari Ini
  - Minggu Ini
  - Bulan Ini
  - Tahun Ini
  - Custom Range

- [ ] **Transaction List**
  - Display all transactions
  - Sort by date (newest first)
  - Show category, amount, account
  - Swipe to delete

- [ ] **Edit Transaction**
  - Tap to edit
  - Update fields
  - Save changes → sync to cloud

- [ ] **Delete Transaction**
  - Soft delete (deletedAt timestamp)
  - Sync deletion to cloud

---

## 🏦 Accounts & Goals

### Accounts
- [ ] **View All Accounts**
  - List physical accounts
  - Show balances

- [ ] **Create Account**
  - Name, type, icon, color
  - Initial balance

- [ ] **Update Account**
  - Change name, icon, color
  - Adjust balance

### Goals (Savings Targets)
- [ ] **View Goals**
  - List active goals
  - Show progress bars

- [ ] **Create Goal**
  - Name, target amount, deadline
  - Initial amount

- [ ] **Progress Tracking**
  - Visual progress bar
  - Percentage completion
  - Days remaining

- [ ] **Savings as Funding Source** (NEW! ✨)
  - Goals appear in account dropdown as "Tabungan: [Name]"
  - Can use goal balance to fund transactions
  - Transaction deducts from goal balance

---

## 👥 Groups (Shared Finance)

### Group Management
- [ ] **Create Group**
  - Name, description
  - Add members

- [ ] **View Group Details**
  - Members list
  - Shared transactions

- [ ] **Group Transactions**
  - Create transaction under group
  - Scope: 'shared'
  - Visible to all members

---

## 🔧 UI/UX Quality

### Navigation
- [ ] Smooth transitions between screens
- [ ] Back button works correctly
- [ ] Bottom navigation functional

### Loading States
- [ ] Loading indicators visible during data fetch
- [ ] Skeleton screens for better UX
- [ ] Disable buttons during async operations

### Error Handling
- [ ] Clear error messages
- [ ] Retry mechanisms
- [ ] Offline mode gracefully handled

### Responsive Design
- [ ] Works on different screen sizes
- [ ] Portrait and landscape orientations
- [ ] Tablet support (if applicable)

### Performance
- [ ] App launches quickly
- [ ] No lag when scrolling lists
- [ ] Smooth animations
- [ ] Memory usage reasonable

---

## 🌐 Network & Sync

### Online Behavior
- [ ] Auto-sync when online
- [ ] Real-time updates
- [ ] Background sync (periodic)

### Offline Behavior
- [ ] All features work offline
- [ ] Data queued for sync
- [ ] Clear offline indicator

### Sync Recovery
- [ ] Pending items sync when back online
- [ ] Conflict resolution (if any)
- [ ] No data loss

---

## 📱 Device Testing Priority

### High Priority (Must Test)
1. ✅ Login & Register (Supabase Auth)
2. ✅ Create transactions (manual + chat)
3. ✅ Dashboard with new insights & comparison
4. ✅ Transaction history with filters
5. ✅ Savings as funding source
6. ✅ Offline → Online sync

### Medium Priority
7. Groups functionality
8. Goals progress tracking
9. Account management
10. Category management

### Low Priority (Nice to Have)
11. Gold portfolio
12. Push notifications
13. Smart insights scheduling
14. Export/import data

---

## 🐛 Known Issues to Watch

1. **Portfolio showing 0?** → Fixed with formula update
2. **Duplicate icons?** → Fixed by removing emojis
3. **Date filter not working?** → Fixed with template selection
4. **No group filter in history?** → Fixed with ChoiceChips
5. **Savings not as funding source?** → Fixed with virtual accounts

---

## ✅ Pre-Release Checklist

- [ ] All critical features tested
- [ ] Login/Register functional
- [ ] Supabase sync verified
- [ ] Offline mode works
- [ ] UI/UX polished
- [ ] No critical bugs
- [ ] Performance acceptable
- [ ] Ready for production use

---

## 📝 Testing Notes

**Device:** _[Your device model]_  
**OS Version:** _[iOS/Android version]_  
**App Version:** _[Version number]_  
**Test Date:** _[Date]_

### Issues Found:
1. 
2. 
3. 

### Suggestions:
1. 
2. 
3. 

---

**Happy Testing! 🚀**
