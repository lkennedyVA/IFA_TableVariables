USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will update the Org, it will not update OrgTypeId or StatusFlag
	Tables: [organization].[Org]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgUpdateOut](
	 @pnvCode NVARCHAR(25) = N''
	,@pnvName NVARCHAR(50) = N''
	,@pnvDescr NVARCHAR(255) = N''
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Org table (
		 OrgId int
		,OrgTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this Org to a Org already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [organization].[Org]
					WHERE OrgId <> @piOrgId
						AND Name = @pnvName)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[Org]
			SET Code = CASE WHEN @pnvCode = N'' THEN Code ELSE @pnvCode END
				,[Name] = CASE WHEN @pnvName = N'' THEN [Name] ELSE @pnvName END
				,Descr = CASE WHEN @pnvDescr = N'' THEN Descr ELSE @pnvDescr END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.OrgId
				,deleted.OrgTypeId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @Org
			WHERE OrgId = @piOrgId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[Org](OrgId
			--,OrgTypeId
			--,Code
			--,Name
			--,Descr
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT OrgId
			--,OrgTypeId
			--,Code
			--,Name
			--,Descr
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @Org
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgId = OrgId
			FROM @Org;
		END
	END
	ELSE
		SELECT @piOrgId = -3
END
