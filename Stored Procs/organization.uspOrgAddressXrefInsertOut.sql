USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: uspOrgAddressXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2017-06-03
	Descr: This procedure will insert a new record
	Tables: [organization].[OrgAddressXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2017-06-03 - LBD - Created
		2018-07-22 - LSW - Insert new row or return OrgAddressXrefId of existing row.
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgAddressXrefInsertOut](
	 @piOrgId INT
	,@pbiAddressId BIGINT
	,@pfLatitude FLOAT = -1
	,@pfLongitude FLOAT = -1
	,@piStatusFlag INT  
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgAddressXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgAddressXref table (
		OrgAddressXrefId int
		,OrgId int
		,AddressId bigint
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
	IF NOT EXISTS( SELECT 'X' FROM [organization].[OrgAddressXref] AS x WHERE x.OrgId = @piOrgId AND x.AddressId = @pbiAddressId )
		BEGIN
			BEGIN TRANSACTION
			BEGIN TRY
				INSERT INTO [organization].[OrgAddressXref]
					OUTPUT inserted.OrgAddressXrefId
					,inserted.OrgId
					,inserted.AddressId
					,inserted.Latitude
					,inserted.Longitude
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
					INTO @OrgAddressXref
				SELECT @piOrgId
					,@pbiAddressId
					,@pfLatitude
					,@pfLongitude
					,@piStatusFlag
					,SYSDATETIME()
					,@pnvUserName; 
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
				FROM @OrgAddressXref
			END
		END
	ELSE SELECT @piOrgAddressXrefId = x.OrgAddressXrefId FROM [organization].[OrgAddressXref] AS x WHERE x.OrgId = @piOrgId AND x.AddressId = @pbiAddressId
END
