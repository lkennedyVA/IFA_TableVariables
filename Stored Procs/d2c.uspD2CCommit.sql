USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: [d2c].[uspD2CCommit]
	CreatedBy: Larry Dugger
	Descr: This procedure searches [d2c].[Item] using ReferenceNumber
		updates D2CFlag to 2 - 'Dispensed' and DateCommitted.
		Use - EXECUTE [d2c].[uspD2CCommit] @pncReferenceNumber = N'VAX12345678'
	Tables: [d2c].[Item]
	History:
		2022-04-04 - LBD - VALID-211, Created.
		2023-04-03 - CBS - VALID-872: Added exception when unable to update [d2c].[Item] 
		2023-06-08 - HDD - Brisk 2023.1 adde callback information to output
		2023-07-25 - CBS - VALID-1153: Added 'DateActivated' update to indicate when 
			the records been updated. 
		2025-01-08 - LXK - Took out table variable, not being used
*****************************************************************************************/
ALTER   PROCEDURE [d2c].[uspD2CCommit](
	@piD2COrgId INT
	,@pnvReferenceNumber NVARCHAR(11)
	,@pmCheckAmount MONEY
	,@pnvLogKey NVARCHAR(25)
	,@pncVendorId NCHAR(5)
) AS
BEGIN
	SET NOCOUNT ON

	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [d2c].[uspD2CLookup]')),1)
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncProcessKey nchar(25) 
		,@biD2CId bigint
		,@biItemId bigint
		,@iClientAcceptedId int --2023-04-03
		,@iD2CFlag int = 0
		,@iD2COrgId int = @piD2COrgId
		,@ncReferenceNumber nchar(11) = @pnvReferenceNumber
		,@ncPartnerPrefix nchar(3) = LEFT(@pnvReferenceNumber,3)
		,@ncSupportPhone nchar(12) = NULL
		,@nvPartnerName nvarchar(50) = NULL
		,@nvProcessKey nvarchar(25) = NULL
		,@nvCommitCallbackUrl nvarchar(250) = NULL
		,@mPayoutAmount money
		,@nvLogKey nvarchar(25)
		,@ncVendorId nchar(5)
		,@dtDateValidated datetime2(7)
		,@dtDateCommitted datetime2(7)
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID);

--	DECLARE @tblD2C table (
--		 D2CId bigint
--		,ItemId bigint
--		,ProcessKey nvarchar(25)
--		,D2CFlag int
--	);

	BEGIN TRY
		SELECT @biD2CId = i.D2CId
			,@biItemId = i.ItemId
			,@ncProcessKey = i.ProcessKey
			,@iD2CFlag = i.D2CFlag
			,@ncSupportPhone = p.SupportPhone
			,@nvPartnerName = p.PartnerName
			,@nvCommitCallbackUrl = CASE WHEN (p.CommitCallbackUrlEnabled = 1 AND p.CommitCallbackUrl IS NOT NULL)
										THEN p.CommitCallbackUrl
										ELSE NULL 
									END
			,@nvProcessKey = i.ProcessKey
			,@mPayoutAmount = i.PayoutAmount
			,@nvLogKey = i.LogKey
			,@ncVendorId = i.VendorId
			,@dtDateValidated = i.DateValidated
			,@dtDateCommitted = i.DateCommitted
		FROM [d2c].[Partner] p
		LEFT OUTER JOIN [d2c].[Item] i ON p.OrgId = i.OrgId
										AND i.ReferenceNumber = @ncReferenceNumber
		WHERE p.PartnerPrefix = @ncPartnerPrefix;

		IF @iLogLevel > 0 AND @ncProcessKey IS NOT NULL
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
			SET @dtTimerDate  = SYSDATETIME();
		END

		--2023-04-03
		SELECT @iClientAcceptedId = ClientAcceptedId
		FROM [ifa].[Item]
		WHERE ItemId = @biItemId;

		--Updating d2c.Item if it needs it
		IF (@dtDateCommitted IS NULL AND @dtDateValidated IS NOT NULL)
		BEGIN
			 UPDATE i
			 SET D2CFlag = 2      --Dispensed
			    ,D2COrgId = @iD2COrgId --Actual Walmart Location
			    ,DateCommitted = SYSDATETIME()
				,DateActivated = SYSDATETIME() --2023-07-25
			 FROM [d2c].[Item] i
			 WHERE @iD2CFlag = 1
				   AND i.ItemId = @biItemId
				   AND @iClientAcceptedId = 6 --D2C
				   AND @mPayoutAmount = @pmCheckAmount
				   AND @nvLogKey = @pnvLogKey
				   AND @ncVendorId = @pncVendorId
				   AND @dtDateValidated IS NOT NULL
				   AND @dtDateCommitted IS NULL
				   AND D2CId = @biD2CId;

			 --Updating ifa.Item 
			 UPDATE i
			 SET ClientAcceptedId = 1   --Client Accepted
				   ,DateActivated = SYSDATETIME()
			 FROM [ifa].[Item] i
			 WHERE @iD2CFlag = 1
				   AND @mPayoutAmount = @pmCheckAmount
				   AND @nvLogKey = @pnvLogKey
				   AND @ncVendorId = @pncVendorId
				   AND @dtDateValidated IS NOT NULL
				   AND @dtDateCommitted IS NULL
				   AND i.ItemId = @biItemId;
				   --AND i.ClientAcceptedId = 6; --2023-04-03
		END			
	END TRY
	BEGIN CATCH	
		EXEC [error].[uspLogErrorDetailInsertOut2] @psSchemaName = @sSchemaName, @pnvProcessKey=@ncProcessKey, @piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());	
		THROW;
	END CATCH;

	--RETURN TO HAL
	SELECT @biItemId as ItemId
		,ISNULL(@ncSupportPhone,N'N/A') as SupportPhone
		,ISNULL(@nvPartnerName,N'Unknown') as PartnerName
		,CASE WHEN @mPayoutAmount = @pmCheckAmount THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END as PayoutAmountFoundFlag
		,CASE WHEN @nvLogKey = @pnvLogKey THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END as LogKeyFoundFlag
		,CASE WHEN @ncVendorId = @pncVendorId THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END as VendorIdFoundFlag
		,CASE WHEN @dtDateValidated IS NOT NULL THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END as DateValidatedNotNullFoundFlag
		,CASE WHEN @dtDateCommitted IS NULL THEN CONVERT(BIT,1) ELSE CONVERT(BIT,0) END as DateCommittedNullFoundFlag
		,@iD2CFlag as D2CFlag
		,@nvCommitCallbackUrl as CommitCallbackUrl
		,@nvProcessKey as ProcessKey
		;
	--RETURN TO HAL

	--Last Message uses @dtInitial
	IF @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());
END
