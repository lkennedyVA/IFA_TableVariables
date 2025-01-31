USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDetailLevelUpdateOut
	CreatedBy: Larry Dugger
	Date: 2012-20-03
	Descr: This procedure will update the DetailLevel, it will not update the StatusFlag
	Tables: [rule].[DetailLevel]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2012-20-03 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [rule].[uspDetailLevelUpdateOut](
	 @piDetailLevelID INT OUTPUT
	,@pnvCode NVARCHAR(25) = N''
	,@pnvName NVARCHAR(50) = N''
	,@pnvDescr NVARCHAR(255) = N''
	,@piDisplayOrder INT = 0
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @DetailLevel table (
		 DetailLevelId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,DisplayOrder int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'rule';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this checktype to a checktype already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [rule].[DetailLevel]
					WHERE DetailLevelID <> @piDetailLevelId
						AND [Name] = @pnvName)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [rule].[DetailLevel]
			SET Code = CASE WHEN @pnvCode = N'' THEN Code ELSE @pnvCode END
				,[Name] = CASE WHEN @pnvName = N'' THEN [Name] ELSE @pnvName END
				,Descr = CASE WHEN @pnvDescr = N'' THEN Descr ELSE @pnvDescr END
				,DisplayOrder = ISNULL(CASE WHEN @piDisplayOrder <> 0 THEN @piDisplayOrder ELSE NULL END,DisplayOrder)
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.DetailLevelId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.DisplayOrder
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @DetailLevel
			WHERE DetailLevelId = @piDetailLevelId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[DetailLevel](DetailLevelId
			--,Code
			--,Name
			--,Descr
			--,DisplayOrder
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT DetailLevelId
			--,Code
			--,Name
			--,Descr
			--,DisplayOrder
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @DetailLevel
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piDetailLevelId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piDetailLevelID = DetailLevelId
			FROM @DetailLevel;
		END
	END
	ELSE
		SELECT @piDetailLevelID = -3
END
