USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will insert a new record
	Tables: [organization].[OrgXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created, from Validbank
		2015-07-01 - LBD - Modified, added Dimensionid
		2017-06-03 - LBD - Modified, return OrgXrefId if already exists
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgXrefInsertOut](
	 @piDimensionid INT
	,@piOrgParentId INT
	,@piOrgChildId INT
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgXref table (
		OrgXrefId int
		,DimensionId int
		,OrgParentId int
		,OrgChildId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--check if it already exists...
	SELECT @piOrgXrefId = OrgXrefId
	FROM [organization].[OrgXref] ox
	WHERE ox.DimensionId = @piDimensionid
		AND ox.OrgParentId = @piOrgParentId
		AND ox.OrgChildId = @piOrgChildId;
	IF ISNULL(@piOrgXrefId,-1) = -1
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [organization].[OrgXref]
				OUTPUT inserted.OrgXrefId
				,inserted.DimensionId
				,inserted.OrgParentId
				,inserted.OrgChildId
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
				INTO @OrgXref
			SELECT @piDimensionid 
				,@piOrgParentId
				,@piOrgChildId
				,@piStatusFlag
				,SYSDATETIME()
				,@pnvUserName; 
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgXrefId = OrgXrefId
			FROM @OrgXref
		END
	END  --doesn't already exist
END
