USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgAddressXrefStatusFlagExclusiveOut
	CreatedBy: Larry Dugger
	Date: 2017-06-03
	Descr: This procedure will Activate the OrgAddressXref (Set StatusFlag to 2)
	Tables: [organization].[OrgAddressXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2017-06-03 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgAddressXrefStatusFlagExclusiveOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
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
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgAddressXref]
			SET StatusFlag = 2
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
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgAddressXrefId = OrgAddressXrefId
			FROM @OrgAddressXref;
		END
	END
END
