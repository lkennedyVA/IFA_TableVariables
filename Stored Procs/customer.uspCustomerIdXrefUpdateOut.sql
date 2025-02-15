USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerIdXrefUpdate
	CreatedBy: Larry Dugger
	Description: This procedure will update a xref record
	Tables: [customer].[CustomerIdXref]

	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
		2019-10-25 - LBD - Modified, added support for new IdMac64 
		2019-11-13 - LBD - Modified, activated IdMac64
*****************************************************************************************/
ALTER   PROCEDURE [customer].[uspCustomerIdXrefUpdateOut](
	 @piIdTypeId INT
	,@piStateId INT
	,@pnvIdDecrypted NVARCHAR(50)
	,@piOrgId INT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiCustomerIdXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @CustomerIdXref table(
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
	DECLARE @nvIdDecrypted nvarchar(50) = UPPER(RTRIM(LTRIM(@pnvIdDecrypted)))
		,@iIdTypeId int = @piIdTypeId
		,@iOrgId int = @piOrgId
		,@iIdStateId int = @piStateId
		,@iStatusFlag int = @piStatusFlag
		,@vbIdEncrypted varbinary(250) 
		,@vbIdMac varbinary(50)
		,@bIdMac64 binary(64)
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'customer';

	OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY [VALIDASYMKEY] 
	SET @vbIdEncrypted =  ENCRYPTBYKEY(KEY_GUID('VALIDSYMKEY'),@nvIdDecrypted);
	CLOSE SYMMETRIC KEY VALIdSymKey;

	SET @iCurrentTransactionLevel = @@TRANCOUNT;

	SET @iOrgId = [common].[ufnIdTypesRequiringOrgId](@iOrgId,@iIdTypeId);
	SET @iIdStateId = [common].[ufnIdTypesRequiringStateId](@iIdStateId,@iIdTypeId);
	SET @vbIdMac = [ifa].[ufnMAC](@nvIdDecrypted); --2019-11-13
	SET @bIdMac64 = [ifa].[ufnIdMAC64](@iIdTypeId, @iOrgId, @iIdStateId, @nvIdDecrypted); --2019-11-13

	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [customer].[CustomerIdXref]
		SET IdEncrypted = @vbIdEncrypted
			,IdMac = @vbIdMac
			,Last4 = RIGHT(@nvIdDecrypted,4)
			,OrgId = @iOrgId
			,IdStateId = @iIdStateId
			,DateActivated = SYSDATETIME()
			,StatusFlag = @iStatusFlag
			,UserName = @pnvUserName
			,IdMac64 = @bIdMac64
		OUTPUT deleted.CustomerIdXrefId
			,deleted.CustomerId
			,deleted.IdTypeId
			,deleted.IdStateId
			,deleted.IdEncrypted
			,deleted.IdMac
			,deleted.Last4
			,deleted.OrgId
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
			,deleted.IdMac64
		INTO @CustomerIdXref
		WHERE CustomerIdXrefId = @pbiCustomerIdXrefId;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel 
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiCustomerIdXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
END
