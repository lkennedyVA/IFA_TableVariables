USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDeluxeDailyInsert
	CreatedBy: Larry Dugger
	Description: This procedure will insert a new records into
	Tables: [import].[BulkDeluxe]
		,[import].[Deluxe]
		,[authorized].[ItemList]
	Functions: [import].[ufnDeluxeList]

	History:
		2018-05-03 - LBD - Created, doesn't update [authorized].[ItemActivity]
			since we don't actually know how to match....
		2018-10-30 - LBD -Modified, adjsuted size of eCheckPayorArchivedOrLockedReasonCode
		2020-02-03 - LBD - Modified,added additional fields within the header,
			but not capturing for the table yet. CCF1748
		2020-02-12 - LBD - Commented to implement for CCF1883
		2020-03-05 - LBD - Modified, increased DeviceId fields size to 128 CCF1898
		2020-03-10 - LBD - Modified, had to adjust for flip of ipaddress and deviceid
			using substring function line 141
		2022-03-24 - CBS - Deluxe changed the format of the 'CheckNumber' field to occasionally
			preface the value with 'VV'. common.ufnCleanNumber removes non-numeric characters
		2022-03-25 - CBS - Rolled back the update from yesterday
		2025-01-14 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER PROCEDURE [import].[uspDeluxeDailyInsert](
	 @pbiFileId BIGINT
	,@pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #DeluxeDailyInsertBulk
	create table #DeluxeDailyInsertBulk(
		 BulkDeluxeId bigint
		,DeluxeId bigint
	);
	drop table if exists #DeluxeDailyInsertConsumed
	create table #DeluxeDailyInsertConsumed(
		 ItemId bigint
		,PayerId bigint
		,CheckNumber nvarchar(50)
		,CheckAmount money
	);
	crop table if exists #DeluxeDailyInsert
	create table #DeluxeDailyInsert(
		 BulkDeluxeId bigint
		,InternalID int
		,PayorCheckingAccountID int
		,eCheckPayorUserID int
		,eCheckIPAddress nvarchar(50) 
		,eCheckPayorStreetLine1 nvarchar(100) 
		,eCheckPayorStreetLine2 nvarchar(100)
		,eCheckPayorCity nvarchar(100)
		,eCheckPayorState nvarchar(50)
		,eCheckPayorZip nvarchar(10)
		,eCheckPayorBrand nvarchar(50)
		,eCheckOriginationType nvarchar(50)
		,TransactionId nvarchar(100)
		,PayorRelationshipWitheChecks datetime2(7)
		,eCheckPayorAccountEnrollmentDate datetime2(7)
		,eCheckPayorArchivedOrLockedDate datetime2(7)
		,eCheckPayorArchivedOrLockedReasonCode nvarchar(512) 
		,eCheckPayorTypeDesc nvarchar(50) 
		,eCheckPayorAverageTimeBetweenIssuance int
		,eCheckPayorCheckReorders int
		,eCheckPayorReorders int
		,eCheckIssuingLimitsInCents int
		,eCheckSigningLimits nvarchar(50)
		,BankName nvarchar(100)
		,AccountOwnershipVerifiedIndicator nvarchar(50)
		,CheckRoutingNumber nvarchar(50)
		,CheckAccountNumber nvarchar(50)
		,CheckNumber nvarchar(50)
		,CheckIssuedDate datetime2(7)
		,CheckAmountInCents int
		,CheckConsumedDate datetime2(7)
		,PayeeLockboxID int
		,PayeeID nvarchar(50)
		--2020-03-05 ,PayeeName nvarchar(50)
		,PayeeName nvarchar(128)
		,PayeeLockboxEnrollmentDate datetime2(7)
		,PayeeOriginationDate datetime2(7)
		,PayeeTotaleChecksReceived int
		,PayeeAveAmountReceived int
		,PayeeAddressLine1 nvarchar(100)
		,PayeeAddressLine2 nvarchar(100)
		,PayeeCity nvarchar(100)
		,PayeeST nvarchar(50)
		,PayeeZip nvarchar(10)
		,PayeeBusinessName nvarchar(100)
		,PayeePrimaryConsumerName nvarchar(100)
		,APIPreAuthClientRequestID nvarchar(50)
		,APITransactClientRequestID nvarchar(50)
		,PayorIpAddress nvarchar(50)
		--2020-03-05 ,PayorDeviceId nvarchar(100)
		,PayorDeviceId nvarchar(128)
		,PayeeIpAddress nvarchar(50)
		--2020-03-05 ,PayeeDeviceId nvarchar(100))
		,PayeeDeviceId nvarchar(128)
		,ItemId bigint
		,Processed bit
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iDeluxePosOrgId int
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import'
		,@bExpectedHeader bit=0;

	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	
	SELECT @iDeluxePosOrgId = OrgId
	FROM [organization].[Org]
	WHERE ExternalCode = 'DeluxePos'; 
	-- SELECT @bExpectedHeader = CASE WHEN FileRow = '"InternalID","PayorCheckingAccountID","eCheckPayorUserID","eCheckIPAddress","eCheckPayorStreetLine1","eCheckPayorStreetLine2","eCheckPayorCity","eCheckPayorState","eCheckPayorZip","eCheckPayorBrand","eCheckOriginationType","TransactionId","PayorRelationshipWitheChecks","eCheckPayorAccountEnrollmentDate","eCheckPayorArchivedOrLockedDate","eCheckPayorArchivedOrLockedReasonCode","eCheckPayorTypeDesc","eCheckPayorAverageTimeBetweenIssuance","eCheckPayorCheckReorders","eCheckPayorReorders","eCheckIssuingLimitsInCents","eCheckSigningLimits","BankName","AccountOwnershipVerifiedIndicator","CheckRoutingNumber","CheckAccountNumber","CheckNumber","CheckIssuedDate","CheckAmountInCents","CheckConsumedDate","PayeeLockboxID","PayeeID","PayeeName","PayeeLockboxEnrollmentDate","PayeeOriginationDate","PayeeTotaleChecksReceived","PayeeAveAmountReceived","PayeeAddress(Line1)","PayeeAddress(Line2)","PayeeCity","PayeeST","PayeeZip","PayeeBusinessName","PayeePrimaryConsumerName","APIPreAuthClientRequestID","APITransactClientRequestID"' THEN 1 ELSE 0 END Pre-2020-02-05
	SELECT @bExpectedHeader = CASE WHEN FileRow = '"InternalID","PayorCheckingAccountID","eCheckPayorUserID","eCheckIPAddress","eCheckPayorStreetLine1","eCheckPayorStreetLine2","eCheckPayorCity","eCheckPayorState","eCheckPayorZip","eCheckPayorBrand","eCheckOriginationType","TransactionId","PayorRelationshipWitheChecks","eCheckPayorAccountEnrollmentDate","eCheckPayorArchivedOrLockedDate","eCheckPayorArchivedOrLockedReasonCode","eCheckPayorTypeDesc","eCheckPayorAverageTimeBetweenIssuance","eCheckPayorCheckReorders","eCheckPayorReorders","eCheckIssuingLimitsInCents","eCheckSigningLimits","BankName","AccountOwnershipVerifiedIndicator","CheckRoutingNumber","CheckAccountNumber","CheckNumber","CheckIssuedDate","CheckAmountInCents","CheckConsumedDate","PayeeLockboxID","PayeeID","PayeeEmail","PayeeName","PayeeLockboxEnrollmentDate","PayeeOriginationDate","PayeeTotaleChecksReceived","PayeeAveAmountReceived","PayeeAddress(Line1)","PayeeAddress(Line2)","PayeeCity","PayeeST","PayeeZip","PayeeBusinessName","PayeePrimaryConsumerName","APIPreAuthClientRequestID","APITransactClientRequestID","PayorIpAddress","PayorDeviceId","PayeeIpAddress","PayeeDeviceId"' THEN 1 ELSE 0 END
	FROM [import].[BulkDeluxe]
	WHERE FileId = @pbiFileId
		AND RowType = 'H';

	IF @bExpectedHeader = 1 
	BEGIN
		INSERT INTO #DeluxeDailyInsert(BulkDeluxeId, InternalID, PayorCheckingAccountID, eCheckPayorUserID, eCheckIPAddress, eCheckPayorStreetLine1 
			,eCheckPayorStreetLine2, eCheckPayorCity, eCheckPayorState, eCheckPayorZip, eCheckPayorBrand, eCheckOriginationType, TransactionId 
			,PayorRelationshipWitheChecks, eCheckPayorAccountEnrollmentDate, eCheckPayorArchivedOrLockedDate, eCheckPayorArchivedOrLockedReasonCode
			,eCheckPayorTypeDesc, eCheckPayorAverageTimeBetweenIssuance, eCheckPayorCheckReorders, eCheckPayorReorders, eCheckIssuingLimitsInCents 
			,eCheckSigningLimits, BankName, AccountOwnershipVerifiedIndicator, CheckRoutingNumber, CheckAccountNumber, CheckNumber, CheckIssuedDate 
			,CheckAmountInCents, CheckConsumedDate, PayeeLockboxID, PayeeID, PayeeName, PayeeLockboxEnrollmentDate, PayeeOriginationDate, PayeeTotaleChecksReceived 
			,PayeeAveAmountReceived, PayeeAddressLine1, PayeeAddressLine2, PayeeCity, PayeeST, PayeeZip, PayeeBusinessName, PayeePrimaryConsumerName 
			,APIPreAuthClientRequestID, APITransactClientRequestID, PayorDeviceId, PayorIpAddress, PayeeDeviceId, PayeeIpAddress, Processed, StatusFlag, DateActivated, UserName)
			--PayorDeviceId, PayorIpAddress, PayeeDeviceId, PayeeIpAddress are intentionaly switched do to the data in the file
		SELECT bd.BulkDeluxeId, InternalID, PayorCheckingAccountID, eCheckPayorUserID, eCheckIPAddress, eCheckPayorStreetLine1 
			,eCheckPayorStreetLine2, eCheckPayorCity, eCheckPayorState, eCheckPayorZip, eCheckPayorBrand, eCheckOriginationType, TransactionId 
			,PayorRelationshipWitheChecks, eCheckPayorAccountEnrollmentDate, eCheckPayorArchivedOrLockedDate, eCheckPayorArchivedOrLockedReasonCode
			,eCheckPayorTypeDesc, eCheckPayorAverageTimeBetweenIssuance, eCheckPayorCheckReorders, eCheckPayorReorders, eCheckIssuingLimitsInCents 
			,eCheckSigningLimits, BankName, AccountOwnershipVerifiedIndicator, CheckRoutingNumber, CheckAccountNumber, CheckNumber, CheckIssuedDate 
			,CheckAmountInCents, CheckConsumedDate, PayeeLockboxID, PayeeID, PayeeName, PayeeLockboxEnrollmentDate, PayeeOriginationDate, PayeeTotaleChecksReceived 
			,PayeeAveAmountReceived, PayeeAddressLine1, PayeeAddressLine2, PayeeCity, PayeeST, PayeeZip, PayeeBusinessName, PayeePrimaryConsumerName 
			,APIPreAuthClientRequestID, APITransactClientRequestID, PayorIpAddress, SUBSTRING(PayorDeviceId,1,50), PayeeIpAddress, SUBSTRING(PayeeDeviceId,1,50), 0, 1, SYSDATETIME(), @pnvUsername
		FROM [import].[BulkDeluxe] bd
		CROSS APPLY [import].[ufnDeluxeList](bd.FileRow,',',1) dl
		WHERE FileId = @pbiFileId	--just the file indicated
			AND RowType = 'D'		--just pickup the detail rows, no headers or tails
			AND Processed = 0;		--only those we haven't inserted
		IF EXISTS (SELECT 'X' FROM #DeluxeDailyInsert)
		BEGIN
			BEGIN TRY
				INSERT INTO [import].[Deluxe](BulkDeluxeId, InternalID, PayorCheckingAccountID, eCheckPayorUserID, eCheckIPAddress, eCheckPayorStreetLine1 
					,eCheckPayorStreetLine2, eCheckPayorCity, eCheckPayorState, eCheckPayorZip, eCheckPayorBrand, eCheckOriginationType, TransactionId 
					,PayorRelationshipWitheChecks, eCheckPayorAccountEnrollmentDate, eCheckPayorArchivedOrLockedDate, eCheckPayorArchivedOrLockedReasonCode
					,eCheckPayorTypeDesc, eCheckPayorAverageTimeBetweenIssuance, eCheckPayorCheckReorders, eCheckPayorReorders, eCheckIssuingLimitsInCents 
					,eCheckSigningLimits, BankName, AccountOwnershipVerifiedIndicator, CheckRoutingNumber, CheckAccountNumber, CheckNumber, CheckIssuedDate 
					,CheckAmountInCents, CheckConsumedDate, PayeeLockboxID, PayeeID, PayeeName, PayeeLockboxEnrollmentDate, PayeeOriginationDate, PayeeTotaleChecksReceived 
					,PayeeAveAmountReceived, PayeeAddressLine1, PayeeAddressLine2, PayeeCity, PayeeST, PayeeZip, PayeeBusinessName, PayeePrimaryConsumerName 
					,APIPreAuthClientRequestID, APITransactClientRequestID, PayorIpAddress, PayorDeviceId, PayeeIpAddress, PayeeDeviceId, Processed, StatusFlag, DateActivated, UserName)
					OUTPUT inserted.BulkDeluxeId
						,inserted.DeluxeId
					INTO #DeluxeDailyInsertBulk
				SELECT BulkDeluxeId, InternalID, PayorCheckingAccountID, eCheckPayorUserID, eCheckIPAddress, eCheckPayorStreetLine1 
					,eCheckPayorStreetLine2, eCheckPayorCity, eCheckPayorState, eCheckPayorZip, eCheckPayorBrand, eCheckOriginationType, TransactionId 
					,PayorRelationshipWitheChecks, eCheckPayorAccountEnrollmentDate, eCheckPayorArchivedOrLockedDate, eCheckPayorArchivedOrLockedReasonCode
					,eCheckPayorTypeDesc, eCheckPayorAverageTimeBetweenIssuance, eCheckPayorCheckReorders, eCheckPayorReorders, eCheckIssuingLimitsInCents 
					,eCheckSigningLimits, BankName, AccountOwnershipVerifiedIndicator, CheckRoutingNumber, CheckAccountNumber, CheckNumber, CheckIssuedDate 
					,CheckAmountInCents, CheckConsumedDate, PayeeLockboxID, PayeeID, PayeeName, PayeeLockboxEnrollmentDate, PayeeOriginationDate, PayeeTotaleChecksReceived 
					,PayeeAveAmountReceived, PayeeAddressLine1, PayeeAddressLine2, PayeeCity, PayeeST, PayeeZip, PayeeBusinessName, PayeePrimaryConsumerName 
					,APIPreAuthClientRequestID, APITransactClientRequestID, PayorIpAddress, PayorDeviceId, PayeeIpAddress, PayeeDeviceId, Processed, StatusFlag, DateActivated, UserName
				FROM #DeluxeDailyInsert
				ORDER BY BulkDeluxeId;

				UPDATE be
					SET be.Processed = 1
				FROM [import].[BulkDeluxe] be
				INNER JOIN #DeluxeDailyInsertBulk tbe on be.BulkDeluxeId = tbe.BulkDeluxeId;

				UPDATE ia 
					SET ia.AuthorizeFlag = 0 --PreAuthorizedRevoked
				OUTPUT inserted.Itemid 
					,inserted.PayerId
					,inserted.CheckNumber
					,inserted.CheckAmount
					INTO #DeluxeDailyInsertConsumed
				FROM [authorized].[ItemActivity] ia
				INNER JOIN [payer].[Payer] p on ia.PayerId = p.PayerId
				INNER JOIN [import].[Deluxe] d on p.RoutingNumber = d.CheckRoutingNumber
												and p.AccountNumber = d.CheckAccountNumber
												and ia.CheckNumber = d.CheckNumber --2022-03-24, 2022-03-25
												--and ia.CheckNumber = [common].[ufnCleanNumber](d.CheckNumber) --2022-03-24,2022-03-25
				INNER JOIN #DeluxeDailyInsert d2 on d.BulkDeluxeId = d2.BulkDeluxeId
				WHERE ia.AuthorizeFlag = 1
					AND ia.OrgId = @iDeluxePosOrgId --the initial authorization is always from DeluxPos
					AND ISNULL(d.CheckConsumedDate,'') <> ''; --only revoke what has been approved....
	
				UPDATE d
				SET d.ItemId = c.ItemId --Applied to ItemActivity
					,d.Processed = 1 --2022-03-24
				FROM #DeluxeDailyInsertConsumed c
				INNER JOIN [payer].[Payer] p on c.PayerId = p.PayerId
				INNER JOIN [import].[Deluxe] d on p.RoutingNumber = d.CheckRoutingNumber
												and p.AccountNumber = d.CheckAccountNumber
												and c.CheckNumber = d.CheckNumber; --2022-03-24, 2022-03-25
												--and c.CheckNumber = [common].[ufnCleanNumber](d.CheckNumber); --2022-03-24, 2022-03-25
												
											
			END TRY
			BEGIN CATCH
				EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
				RETURN
			END CATCH;
		END
	END
	ELSE
	BEGIN
		RAISERROR ('Header format not recognized', 16, 1);
		RETURN
	END
END
