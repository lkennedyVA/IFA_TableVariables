USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgXrefUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will update the OrgXref, it will not update the StatusFlag
	Tables: [organization].[OrgXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created, from Validbank
		2015-07-01 - LBD - Modified, added Dimensionid
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgXrefUpdateOut](
	 @piDimensionId INT = -1
	,@piOrgParentId INT = -1
	,@piOrgChildId INT = -1
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
	--Will Not update this xref to a record already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [organization].[OrgXref]
					WHERE OrgXrefId <> @piOrgXrefId
							AND DimensionId = @piDimensionId
						AND OrgParentId = @piOrgParentId
						AND OrgChildId = @piOrgChildId)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgXref]
			SET DimensionId = CASE WHEN @piDimensionId = -1 THEN DimensionId ELSE @piDimensionId END
				,OrgParentId = CASE WHEN @piOrgParentId = -1 THEN OrgParentId ELSE @piOrgParentId END
				,OrgChildId = CASE WHEN @piOrgChildId = -1 THEN OrgChildId ELSE @piOrgChildId END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.OrgXrefId
				,deleted.DimensionId
				,deleted.OrgParentId
				,deleted.OrgChildId
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @OrgXref
			WHERE OrgXrefId = @piOrgXrefId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[OrgXref](OrgXrefId
			--	,DimensionId
			--,OrgParentId
			--,OrgChildId
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT OrgXrefId
			--	,DimensionId
			--,OrgParentId
			--,OrgChildId
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @OrgXref
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
			FROM @OrgXref;
		END
	END
	ELSE
		SELECT @piOrgXrefId = -3
END
