USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgAddressXrefUpdateOut
	CreatedBy: Larry Dugger
	Descr: This procedure will update the OrgAddressXref, it will not update the StatusFlag
	Tables: [organization].[OrgAddressXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2017-06-03 - LBD - Created
		2017-11-08 - LBD - Modified, added StatusFlag
		2018-07-09 - LBD - Modified, added lat and long
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgAddressXrefUpdateOut](
	 @piOrgId INT = -1
	,@pbiAddressId BIGINT = -1
	,@pfLatitude FLOAT = -1
	,@pfLongitude FLOAT = -1
	,@piStatusFlag INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgAddressXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgAddressXref table (
		 OrgAddressXrefId int
		,OrgId int
		,AddressId int
		,Latitude float
		,Longitude float
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this xref to one already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [organization].[OrgAddressXref]
					WHERE OrgAddressXrefId <> @piOrgAddressXrefId
						AND OrgId = @piOrgId
						AND AddressId = @pbiAddressId)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgAddressXref]
			SET OrgId = CASE WHEN @piOrgId = -1 THEN OrgId ELSE @piOrgId END
				,AddressId = CASE WHEN @pbiAddressId = -1 THEN AddressId ELSE @pbiAddressId END
				,Latitude = CASE WHEN @pfLatitude = -1 THEN Latitude ELSE @pfLatitude END
				,Longitude = CASE WHEN @pfLongitude = -1 THEN Longitude ELSE @pfLongitude END
				,StatusFlag = CASE WHEN @piStatusFlag = -1 THEN StatusFlag ELSE @piStatusFlag END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.OrgAddressXrefId
				,deleted.OrgId
				,deleted.AddressId
				,deleted.Latitude
				,deleted.Longitude
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @OrgAddressXref
			WHERE OrgAddressXrefId = @piOrgAddressXrefId;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgAddressXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
			THROW
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgAddressXrefId = OrgAddressXrefId
			FROM @OrgAddressXref;
		END
	END
	ELSE
		SELECT @piOrgAddressXrefId = -3
END
