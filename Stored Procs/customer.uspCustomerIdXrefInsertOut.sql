USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerIdXrefInsertOut
	CreatedBy: Larry Dugger
	Description: This procedure will insert a new Id xref record, defaults OrgId to 0
		for all id types except 'Client Provided Identifier'
	Tables: [customer].[CustomerIdXref]
	History:
		2015-06-10 - LBD - Created
		2016-06-10 - LBD - Modified, to use same method as uspCustomerIdXrefSelectOut
		2017-08-21 - LBD - Modified, adjusted output message to new V106 exceptions
		2019-06-21 - LBD - Modified, removed the varbinary(50) force
		2019-10-22 - LBD - Modified, added new IdMac64, remove @pnvDecryptedKey parameter
		2019-11-13 - LBD - Modified, activated IdMac64
*****************************************************************************************/
ALTER   PROCEDURE [customer].[uspCustomerIdXrefInsertOut](
	 @pbiCustomerId BIGINT 
	,@piIdTypeId INT
	,@piStateId INT
	,@pnvIdDecrypted NVARCHAR(50)
	,@pvbIdEncrypted VARBINARY(250)
	,@piOrgId INT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiCustomerIdXrefId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblCustomerIdXref table(
		 CustomerIdXrefId bigint
		,CustomerId bigint
		,IdTypeId int
		,IdStateId int
		,IdEncrypted varbinary(250)
		,IdMac varbinary(50)
		,Last4 nvarchar(4)
		,OrgId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		,IdMac64 binary(64)
	);

	DECLARE @biCustomerId bigint = @pbiCustomerId
		,@biCustomerIdXrefId bigint
		,@iIdTypeId int = @piIdTypeId
		,@iIdStateId int = @piStateId
		,@nvIdDecrypted nvarchar(50) = UPPER(RTRIM(LTRIM(@pnvIdDecrypted)))
		,@vbIdEncrypted varbinary(250) = @pvbIdEncrypted
		,@iOrgId int = @piOrgId
		,@iStatusFlag int = @piStatusFlag
		,@nvUserName nvarchar(100) = @pnvUserName
		,@vbIdMac varbinary(50)
		,@bIdMac64 binary(64)
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'customer';

	SET @iOrgId = [common].[ufnIdTypesRequiringOrgId](@iOrgId,@iIdTypeId)
	SET @iIdStateId = [common].[ufnIdTypesRequiringStateId](@iIdStateId,@iIdTypeId);
	SET @vbIdMac = [ifa].[ufnMAC](@nvIdDecrypted);
	SET @bIdMac64 = [ifa].[ufnIdMac64](@iIdTypeId, @iOrgId, @iIdStateId, @nvIdDecrypted);

	SET @pbiCustomerIdXrefId = 0;
	IF @piStatusFlag = -1
		SET @piStatusFlag = 1;

	IF ISNULL(@pnvIdDecrypted, '') = ''
		RAISERROR ('IdNumber is required', 16, 1);

	SELECT @biCustomerIdXrefId = CustomerIdXrefId
	FROM  [customer].[CustomerIdXref] 
	WHERE IdMac64 =  @bIdMac64;
	--2019-11-13 WHERE IdMac = [ifa].[ufnMAC](@nvIdDecrypted)
	--	AND IdTypeId = @iIdTypeId
	--	AND IdStateId = @iIdStateId
	--	AND OrgId = @iOrgId;
	IF ISNULL(@biCustomerIdXrefId,0) = 0
	BEGIN
		SET @iCurrentTransactionLevel = @@TRANCOUNT;
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [customer].[CustomerIdXref]
				OUTPUT inserted.CustomerIdXrefId
					,inserted.CustomerId
					,inserted.IdTypeId
					,inserted.IdStateId
					,inserted.IdEncrypted
					,inserted.IdMac
					,inserted.Last4
					,inserted.OrgId
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
					,inserted.IdMac64
				INTO @tblCustomerIdXref
			SELECT @biCustomerId
				,@iIdTypeId
				,@iIdStateId
				,@vbIdEncrypted
				--2019-11-13 ,[ifa].[ufnMAC](@nvIdDecrypted)
				,@vbIdMac
				,RIGHT(@nvIdDecrypted,4)
				,@iOrgId
				,@piStatusFlag
				,SYSDATETIME()
				,@pnvUserName
				-- 2019-11-13,[ifa].[ufnIdMac64](@iIdTypeId, @iOrgId, @iIdStateId, @nvIdDecrypted);
				,@bIdMac64
			SELECT @pbiCustomerIdXrefId = CustomerIdXrefId
			FROM @tblCustomerIdXref;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel 
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @pbiCustomerIdXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
			THROW;
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			COMMIT TRANSACTION;
	END
	ELSE
		SET @pbiCustomerIdXrefId = @biCustomerIdXrefId;
END
