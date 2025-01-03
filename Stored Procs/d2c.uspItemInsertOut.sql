USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [d2c].[uspItemInsertOut]
	CreatedBy: Larry Dugger
	Descr: This procedure will insert [d2c].[Item] record.
	Tables: [d2c].[Item]
	History:
		2022-04-04 - LBD - VALID-211, Created.
*****************************************************************************************/
ALTER PROCEDURE [d2c].[uspItemInsertOut](
	 @ptblDecisionField [ifa].[DecisionFieldType] READONLY
	,@ptblItem [ifa].[ItemType] READONLY
	,@ptblMiscStat [ifa].[MiscStatType] READONLY
	,@pxD2CStat XML OUTPUT
) AS
BEGIN
	SET NOCOUNT ON
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [d2c].[uspItemInsertOut]')),3)
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME(); --used for complete time in procedure
	--2022-04-04
	DECLARE @tblD2C table (
		 D2CId bigint
		,ItemId bigint
		,LeadingZeros nchar(4)
		,ReferenceNumber nchar(11)
		,Amount nchar(8)
		,VendorId nchar(5)
		);

	DECLARE @ncProcessKey nchar(25)
		,@nvCustomerFirstName nvarchar(50)				
		,@nvCustomerLastName nvarchar(50)				
		,@ncStateAbbv nchar(2)					
		,@nvZipCode nvarchar(5)					
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID);

	SELECT @ncProcessKey = ProcessKey
	FROM @ptblDecisionField;

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
		SET @dtTimerDate  = SYSDATETIME();
	END

	BEGIN TRY
		SELECT @nvCustomerFirstName = LEFT(StatValue,50) FROM @ptblMiscStat WHERE StatName = N'D2CCustomerFirstName';
		SELECT @nvCustomerLastName = LEFT(StatValue,50) FROM @ptblMiscStat WHERE StatName = N'D2CCustomerLastName';
		SELECT @ncStateAbbv = LEFT(StatValue,2) FROM @ptblMiscStat WHERE StatName = N'D2CStateAbbv';
		SELECT @nvZipCode = LEFT(StatValue,5) FROM @ptblMiscStat WHERE StatName = N'D2CZipCode';
	
		INSERT INTO [d2c].[Item](OrgId, ProcessId, ProcessKey, ItemId, CheckAmount, FeeAmount
			,PayoutAmount, CustomerFirstName, CustomerLastName, ZipCode, StateAbbv
			--defaulted in table [LeadingZeros], [ReferenceNumber], [Amount], [VendorId]
			,PartnerPrefix, D2CFlag, DateActivated, DateCreated)
			OUTPUT inserted.D2CId
				,inserted.ItemId
				,inserted.LeadingZeros
				,inserted.ReferenceNumber
				,inserted.Amount
				,inserted.VendorId
			INTO @tblD2C
		SELECT df.OrgId, df.ProcessId, df.ProcessKey, i.ItemId, i.CheckAmount, i.Fee
			,[Amount], @nvCustomerFirstName, @nvCustomerLastName, @nvZipCode, @ncStateAbbv
			,p.PartnerPrefix, 1, SYSDATETIME(), SYSDATETIME()
		FROM @ptblItem i 
		INNER JOIN @ptblDecisionField df ON i.ProcessId = df.ProcessId
		INNER JOIN [d2c].[Partner] p ON df.OrgId = p.OrgId;

		SELECT @pxD2CStat = (SELECT s.ItemId, s.StatName, s.StatValue
							FROM (SELECT i1.ItemId
									,TRY_CONVERT(NVARCHAR(128),N'D2CFlag') as StatName
									,TRY_CONVERT(NVARCHAR(100),N'1') as StatValue
								FROM @ptblItem i1
								INNER JOIN @tblD2C d1 ON i1.ItemId = d1.ItemId
								UNION ALL
								SELECT i2.ItemId
									,TRY_CONVERT(NVARCHAR(128),N'D2CBarcode') as StatName
									,TRY_CONVERT(NVARCHAR(100),d2.LeadingZeros+d2.ReferenceNumber+d2.Amount+d2.VendorId) as StatValue
								FROM @ptblItem i2
								INNER JOIN @tblD2C d2 ON i2.ItemId = d2.ItemId
								) as s
							ORDER BY 1
							FOR XML PATH ('Stat')--element set identifier
						)
	END TRY
	BEGIN CATCH	
		EXEC [error].[uspLogErrorDetailInsertOut2] @psSchemaName = @sSchemaName, @pnvProcessKey=@ncProcessKey, @piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());	
		THROW;
	END CATCH;
	
	--Last Message uses @dtInitial
	IF @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());

END
