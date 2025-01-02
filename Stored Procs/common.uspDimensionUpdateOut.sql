USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspDimensionUpdateOut]    Script Date: 1/2/2025 8:16:44 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDimensionUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will update the Dimension, it will not update the StatusFlag
	Tables: [common].[Dimension]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspDimensionUpdateOut](
	 @pnvCode NVARCHAR(25) = N''
	,@pnvName NVARCHAR(50) = N''
	,@pnvDescr NVARCHAR(255) = N''
	,@piDisplayOrder INT = 0
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piDimensionId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Dimension table (
		 DimensionId int
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
		,@sSchemaName nvarchar(128);
	SET @sSchemaName = N'common';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this Dimension to a Dimension already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [common].[Dimension]
					WHERE DimensionId <> @piDimensionId
						AND Name = @pnvName)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [common].[Dimension]
			SET Code = CASE WHEN @pnvCode = N'' THEN Code ELSE @pnvCode END
				,[Name] = CASE WHEN @pnvName = N'' THEN [Name] ELSE @pnvName END
				,Descr = CASE WHEN @pnvDescr = N'' THEN Descr ELSE @pnvDescr END
				,DisplayOrder = ISNULL(CASE WHEN @piDisplayOrder <> 0 THEN @piDisplayOrder ELSE NULL END,DisplayOrder)
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.DimensionId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.DisplayOrder
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @Dimension
			WHERE DimensionId = @piDimensionId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[Dimension](DimensionId
			--,Code
			--,Name
			--,Descr
			--,DisplayOrder
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT DimensionId
			--,Code
			--,Name
			--,Descr
			--,DisplayOrder
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @Dimension
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piDimensionId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piDimensionId = DimensionId
			FROM @Dimension;
		END
	END
	ELSE
		SELECT @piDimensionId = -3
END
