USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgXrefStatusFlagSetOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will Activate the OrgXref (Set StatusFlag)
	Tables: [organization].[OrgXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created, from Validbank
		2015-07-01 - LBD - Modified, added Dimensionid
		2015-12-01 - CBS - Modified, added @piDimensionid parameter; Added 
			Dimension to WHERE clause
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgXrefStatusFlagSetOut](
	 @piDimensionId INT
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
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgXref]
			SET StatusFlag = 1
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
			WHERE OrgXrefId = @piOrgXrefId
				AND DimensionId = @piDimensionId;
			----Anytime an update occurs we place an original copy in an archive table
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
END
