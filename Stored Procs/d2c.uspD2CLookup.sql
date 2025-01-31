USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: [d2c].[uspD2CLookup]
	CreatedBy: Larry Dugger
	Descr: This procedure searches [d2c].[Item] using ReferenceNumber
		Returns the Itemid if found.
		Use - EXECUTE [d2c].[uspD2CLookup] @pncReferenceNumber = N'VAX12345678'
	Tables: [d2c].[Item]
	History:
		2022-04-04 - LBD - VALID-211, Created.
		2023-07-25 - CBS - VALID-1153: Added 'DateActivated' update to indicate when 
			the records been updated.
		2023-08-13 - HDD TFS #4162 allow expired items to be selected so I can report on the expiration
		2025-01-08 - LXK - Took ot table variable, not being used
*****************************************************************************************/
ALTER PROCEDURE [d2c].[uspD2CLookup](
	 @pnvReferenceNumber NVARCHAR(11)
	,@pmCheckAmount MONEY
	,@pnvLogKey NVARCHAR(25)
	,@pncVendorId NCHAR(5)
) AS
BEGIN
	SET NOCOUNT ON

--	DECLARE @tblFoundIt table (D2CId bigint);

	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [d2c].[uspD2CLookup]')),1)
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncProcessKey nchar(25) 
		,@biD2CId bigint
		,@iD2CFlag int
		,@biItemId bigint
		,@ncReferenceNumber nchar(11) = @pnvReferenceNumber
		,@ncPartnerPrefix nchar(3) = LEFT(@pnvReferenceNumber,3)
		,@ncSupportPhone nchar(12) = NULL
		,@nvPartnerName nvarchar(50) = NULL
		,@mCheckAmount money
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID);

	BEGIN TRY
		SELECT @biD2CId = i.D2CId 
			,@iD2CFlag = i.D2CFlag
			,@ncProcessKey = i.ProcessKey
			,@biItemId = i.ItemId
			,@ncSupportPhone = p.SupportPhone
			,@nvPartnerName = p.PartnerName
		FROM [d2c].[Partner] p
		LEFT OUTER JOIN [d2c].[Item] i ON p.OrgId = i.OrgId 
									AND i.ReferenceNumber = @ncReferenceNumber
									AND i.VendorId = @pncVendorId
									AND i.PayoutAmount = @pmCheckAmount --This is their field name
		WHERE p.PartnerPrefix = @ncPartnerPrefix;

		IF @iLogLevel > 0
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
			SET @dtTimerDate  = SYSDATETIME();
		END

	END TRY
	BEGIN CATCH	
		EXEC [error].[uspLogErrorDetailInsertOut2] @psSchemaName = @sSchemaName, @pnvProcessKey=@ncProcessKey, @piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());	
		THROW;
	END CATCH;

	--Can't do anything to a record that is already 'not dispensable' or 'dispensed'
	UPDATE i
	SET LogKey = @pnvLogKey
		,DateLookedup = SYSDATETIME()
		,DateValidated = NULL
		,DateActivated = SYSDATETIME() --2023-07-25
	FROM [d2c].[Item] i
	WHERE @iD2CFlag = 1
		AND D2CId = @biD2CId;--We found the record

	--RETURN TO HAL
	SELECT CASE WHEN @iD2CFlag in (1, -1) THEN @biItemId ELSE NULL END  as ItemId
		,ISNULL(@ncSupportPhone,N'N/A') as SupportPhone
		,ISNULL(@nvPartnerName,N'Unknown') as PartnerName
		,@iD2CFlag as D2CFlag; 
	--RETURN TO HAL	

	--Last Message uses @dtInitial
	IF @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());
END
