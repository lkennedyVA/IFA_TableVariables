USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspProcessTDBException
	CreatedBy: Larry Dugger
	Description: This procedure will process all of the unprocessed records

	Tables: [import].[File]
		,[import].[BulkException]

	Procedures: [import].[uspProcessConfirmationRequest]	returns error statuses
		,[import].[uspProcessReverseRequest]				returns error statuses

	History:
		2020-06-04 - LBD - Created
		2025-01-14 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [import].[uspProcessTDBException](
	 @pnvUserName NVARCHAR(100)
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ProcessTDBException
	create table #ProcessFTBException(
		FTBExceptionId bigint
	);
	DECLARE @tblItemConfirmRequest [ifa].[ItemConfirmRequestType];
/* 	drop table if exists #ProcessTDBExceptionItemConfirm
	create table #ProcessTDBExceptionItemConfirm(
	[ItemKey] [nvarchar](25) NULL,
	[ClientItemId] [nvarchar](50) NULL,
	[ClientAccepted] [int] NULL,
	[Fee] [money] NULL,
	[PayoutAmount] [money] NULL
); */
	DECLARE @iOrgId int
		,@biTDBExceptionId bigint
		,@nvProcessKey nvarchar(25)
		,@nvItemKey nvarchar(25)
		,@nvExceptionCode nvarchar(25)
		,@iStatusFlag int = 1
		,@iReverseItemStatusId int = [common].[ufnItemStatus]('Reversed')
		,@iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@iAcceptedClientAcceptedId  int = [common].[ufnClientAccepted]('Accepted')
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import';

	SELECT @iOrgId = OrgId
	FROM [organization].[Org] 
	WHERE ExternalCode = 'TDClnt';

	DECLARE csr_Reverse CURSOR FOR
	SELECT pe.TDBExceptionId,pe.ProcessKey,pe.ItemKey,et.Code
	FROM [import].[TDBException] pe
	INNER JOIN [import].[ExceptionType] et ON pe.ExceptionTypeId = et.ExceptionTypeId
	WHERE (et.Code = 'R'		--exception reversals
			OR et.Code = 'C')	--exception confirms --2017-09-05 LBD
		AND Processed = 0		--only those we haven't processed
	ORDER BY pe.TDBExceptionId;
	OPEN csr_Reverse
	FETCH csr_Reverse into @biTDBExceptionId, @nvProcessKey,@nvItemKey,@nvExceptionCode;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		IF @nvExceptionCode = 'R'
			EXECUTE [import].[uspProcessReverseRequest] @pnvProcessKey=@nvProcessKey, @pnvItemKey=@nvItemKey, @piOrgId=@iOrgId, @pnvUserName=@pnvUserName, @piStatusFlag=@iStatusFlag OUTPUT;
		ELSE IF @nvExceptionCode = 'C'
		BEGIN
			--GRAB data
			INSERT INTO @tblItemConfirmRequest(ItemKey,ClientItemId,ClientAccepted,Fee,PayoutAmount)
			SELECT ItemKey,ClientItemId,@iAcceptedClientAcceptedId,Fee, Amount
			FROM [ifa].[Process] p WITH (READUNCOMMITTED)
			INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
			WHERE p.ProcessKey = @nvProcessKey
				AND i.ItemKey = @nvItemKey;
			IF EXISTS (SELECT 'X' FROM @tblItemConfirmRequest)
				EXECUTE [import].[uspProcessConfirmationRequest] @pnvProcessKey=@nvProcessKey, @piOrgId=@iOrgId, @ptblItemConfirmRequest=@tblItemConfirmRequest, @pnvUserName=@pnvUserName, @piStatusFlag=@iStatusFlag OUTPUT;
			ELSE
				SET @iStatusFlag = [import].[ufnStatusFlag]('DoesntExist');
			DELETE FROM @tblItemConfirmRequest;
		END
		--UPDATE using the StatusFlag received
		UPDATE [import].[TDBException]
			SET Processed = 1
				,StatusFlag = @iStatusFlag
		WHERE TDBExceptionId = @biTDBExceptionId;

		FETCH csr_Reverse into @biTDBExceptionId, @nvProcessKey,@nvItemKey,@nvExceptionCode;
	END
END
