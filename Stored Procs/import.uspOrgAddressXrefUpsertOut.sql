USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgAddressXrefInsertOut
	CreatedBy: Larry Dugger
	Descr: This procedure will insert a new record
	Tables: [organization].[OrgAddressXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2021-02-01 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [import].[uspOrgAddressXrefUpsertOut](
	@pbiSrcRowId BIGINT
	,@pnvSrcTable NVARCHAR(128)
	,@pnvMsg NVARCHAR(255)
	,@piOrgId INT
	,@pbiAddressId BIGINT
	,@pfLatitude FLOAT
	,@pfLongitude FLOAT 
	,@piStatusFlag INT  
	,@pnvUserName NVARCHAR(100) 
	,@piOrgAddressXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @dtStart datetime2(7) = SYSDATETIME()
		,@biActivityTime bigint = 0;
	DECLARE @tblOrgAddressXref table (
		OrgAddressXrefId int
		,OrgId int
		,AddressId bigint
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
		,@biAddressId bigint = @pbiAddressId
		,@fLatitude float = @pfLatitude
		,@fLongitude float = @pfLongitude
		,@iStatusFlag int = @piStatusFlag
		,@nvUserName nvarchar(100) = @pnvUserName
		,@iOrgAddressXrefId int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int = @@TRANCOUNT;

	--Check for an existing OrgAddress Record
	SELECT @iOrgAddressXrefId = oax.OrgAddressXrefId
	FROM [organization].[OrgAddressXref] oax
	WHERE oax.OrgId = @iOrgId
		AND oax.AddressId = @biAddressId;
 
	BEGIN TRANSACTION
	BEGIN TRY
		IF ISNULL(@iOrgAddressXrefId,-1) <> -1
		BEGIN
			SET @nvMsg = 'Update ' + @nvMsg;
			UPDATE [organization].[OrgAddressXref]
				SET Latitude = @fLatitude
					,Longitude = @fLongitude
					,StatusFlag = @iStatusFlag
					,DateActivated = SYSDATETIME()
					,UserName = @nvUserName
				 OUTPUT inserted.OrgAddressXrefId
					,inserted.Latitude
					,inserted.Longitude
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
				 INTO @tblOrgAddressXref(OrgAddressXrefId,Latitude,Longitude,StatusFlag,DateActivated,UserName)
			WHERE OrgAddressXrefId = @iOrgAddressXrefId;
		END
		ELSE 
		BEGIN
			SET @nvMsg = 'Insert ' + @nvMsg;
			INSERT INTO [organization].[OrgAddressXref]
				OUTPUT inserted.OrgAddressXrefId
				,inserted.OrgId
				,inserted.AddressId
				,inserted.Latitude
				,inserted.Longitude
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
				INTO @tblOrgAddressXref
			SELECT @piOrgId
				,@pbiAddressId
				,@pfLatitude
				,@pfLongitude
				,@piStatusFlag
				,SYSDATETIME()
				,@pnvUserName; 
		END
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
			,@iOrgAddressXrefId = OrgAddressXrefId
		FROM @tblOrgAddressXref
	END

	SET @biActivityTime = DATEDIFF(microsecond,@dtStart,sysdatetime());
	--Log the Activity						
	EXECUTE [import].[uspOrganizationLog] 
		 @pbiSrcTableId = @biSrcRowId
		,@pnvSrcTable = @nvSrcTable
		,@pbiDstTableId = @iOrgAddressXrefId
		,@pnvDstTable = N'[organization].[OrgAddressXref]'
		,@pnvMsg = @nvMsg
		,@pbiActivityLength = @biActivityTime
		,@pnvUserName = @nvUserName;
END
