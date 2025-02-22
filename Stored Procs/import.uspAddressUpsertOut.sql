USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [import].[uspAddressInsertOut]
	CreatedBy: Larry Dugger
	Descr: This procedure will insert a new record
	Tables: [common].[Address]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2021-02-01 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [import].[uspAddressUpsertOut](
	@pbiSrcRowId BIGINT
	,@pnvSrcTable NVARCHAR(128)	
	,@pnvMsg NVARCHAR(255)
	,@piOrgId INT
	,@pnvAddress1 NVARCHAR(150)
	,@pnvAddress2 NVARCHAR(150)
	,@pnvCity NVARCHAR(150)
	,@pnvStateAbbv NVARCHAR(2)
	,@pnvZipCode NCHAR(9)
	,@pnvCountry NVARCHAR(50)
	,@pfLatitude FLOAT
	,@pfLongitude FLOAT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100)
	,@pbiAddressId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @dtStart datetime2(7) = SYSDATETIME()
		,@biActivityTime bigint = 0;
	DECLARE @tblAddress table (
		AddressId bigint 
		,Address1 nvarchar(150)
		,Address2 nvarchar(150) 
		,City  nvarchar(100)
		,StateId int
		,ZipCode nchar(5)
		,ZipCodeLast4 nchar(4)
		,Country nvarchar(50)
		,Latitude float
		,Longitude float
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @biSrcRowId bigint = @pbiSrcRowId 
		,@nvSrcTable nvarchar(128) = @pnvSrcTable
		,@iOrgId int = @piOrgId
		,@nvMsg nvarchar(255) = @pnvMsg
		,@nvAddress1 nvarchar(150) = @pnvAddress1
		,@nvAddress2 nvarchar(150) = @pnvAddress2
		,@nvCity nvarchar(150) = @pnvCity
		,@nvZipCodeLast4 nchar(4) = CASE WHEN LEN(@pnvZipCode) = 9 THEN RIGHT(@pnvZipCode,4) ELSE '' END
		,@nvZipCode nchar(9) = LEFT(@pnvZipCode,5) 
		,@nvCountry nvarchar(50) = @pnvCountry
		,@fLatitude float = @pfLatitude
		,@fLongitude float = @pfLongitude
		,@iStatusFlag int = @piStatusFlag
		,@nvUserName nvarchar(100) = @pnvUserName
		,@iStateId int = [common].[ufnState](@pnvStateAbbv)
		,@biAddressId bigint = NULL
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int = @@TRANCOUNT;
 
	--Already exists? 
	--Must be restricted to a universal key fields (OrgId)
	SELECT @biAddressId = AddressId
	FROM [organization].[OrgAddressXref] oax
	WHERE oax.OrgId = @iOrgId;	

	BEGIN TRANSACTION
	BEGIN TRY
		IF ISNULL(@biAddressId, -1) <> -1  --No fields that can't be updated
		BEGIN
			SET @nvMsg = 'Update ' + @nvMsg;
			UPDATE [common].[Address]
			SET Address1 = @nvAddress1
				,Address2 = @nvAddress2
				,City = @nvCity
				,StateId = @iStateId
				,ZipCode = @nvZipCode
				,ZipCodeLast4 = @nvZipCodeLast4
				,Country = @nvCountry
				,Latitude = @fLatitude
				,Longitude = @fLongitude
				,StatusFlag = @iStatusFlag
				,DateActivated = SYSDATETIME()
				,UserName = @nvUserName
				OUTPUT inserted.AddressId
					,inserted.Address1
					,inserted.Address2
					,inserted.City
					,inserted.StateId
					,inserted.ZipCode
					,inserted.ZipCodeLast4
					,inserted.Country
					,inserted.Latitude
					,inserted.Longitude
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
				INTO @tblAddress
			WHERE AddressId = @biAddressId;
		END
		ELSE 
		BEGIN		
			SET @nvMsg = 'Insert ' + @nvMsg;		
			INSERT INTO [common].[Address]
				OUTPUT inserted.AddressId
					,inserted.Address1
					,inserted.Address2
					,inserted.City
					,inserted.StateId
					,inserted.ZipCode
					,inserted.ZipCodeLast4
					,inserted.Country
					,inserted.Latitude
					,inserted.Longitude
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
				INTO @tblAddress
			SELECT @nvAddress1 
				,@nvAddress2 
				,@nvCity 
				,@iStateId 
				,@nvZipCode
				,@nvZipCodeLast4
				,@nvCountry 
				,@fLatitude 
				,@fLongitude 
				,@iStatusFlag 
				,SYSDATETIME() 
				,@nvUserName;
		END
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId = @iErrorDetailId OUTPUT;
		SET @pbiAddressId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		THROW;
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @pbiAddressId = AddressId
			,@biAddressId = AddressId
		FROM @tblAddress
	END

	SET @biActivityTime = DATEDIFF(microsecond,@dtStart,sysdatetime());
	--Log the Activity						
	EXECUTE [import].[uspOrganizationLog] 
		 @pbiSrcTableId = @biSrcRowId
		,@pnvSrcTable = @nvSrcTable
		,@pbiDstTableId = @biAddressId
		,@pnvDstTable = N'[common].[Address]'
		,@pnvMsg = @nvMsg
		,@pbiActivityLength = @biActivityTime
		,@pnvUserName = @nvUserName;
END
